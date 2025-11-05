//
//  RegisterFile.swift
//  swift-mmix
//
//  Created by Jim Dovey on 10/13/25.
//

import MachineKit

/// MMIX Register File with local/marginal/global window system.
///
/// ### Architecture Notes
///
/// - 256 general-purpose registers (`$0`...`$255`)
/// - `$0` is hardwired to zero (reads `0`, writes ignored)
/// - Registers divided by `L` and `G` thresholds:
///   - `0 ≤ i < L`: Local (accessible)
///   - `L ≤ i < G`: Marginal (read as `0`, writes grow `L`)
///   - `G ≤ i < 256`: Global (accessible)
/// - 32 special registers (`rA`, `rB`, ..., `rZZ`)
/// - Register stack for `PUSHJ`/`POP` operations.
public struct MMIXRegisterFile: Sendable {
    // MARK: Storage

    /// General-purpose registers.
    private var general: ContiguousArray<Octa>

    /// Special registers.
    private var special: InlineArray<32, Octa>

    /// Register offset - where logical `$0` maps to in physical hardware.
    ///
    /// This is just a quick accessor/converter for `special[.rO]`.
    @inline(__always)
    private var rO: Int {
        get { Int(truncatingIfNeeded: readSpecial(.rO)) }
        set { writeSpecial(.init(UInt64(bitPattern: .init(newValue))), to: .rO) }
    }

    /// Register stack pointer - total octabytes in memory stack.
    ///
    /// This is just a quick accessor/converter for `special[.rS]`.
    @inline(__always)
    private var rS: Int {
        get { Int(truncatingIfNeeded: readSpecial(.rS)) }
        set { writeSpecial(.init(UInt64(bitPattern: .init(newValue))), to: .rS) }
    }

    /// Local register threshold.
    ///
    /// This is just a quick accessor/converter for `special[.rL]`.
    @inline(__always)
    private var rL: Int {
        get { Int(truncatingIfNeeded: readSpecial(.rL)) }
        set { writeSpecial(.init(UInt64(bitPattern: .init(newValue))), to: .rL) }
    }

    /// Global register threshold.
    ///
    /// This is just a quick accessor/converter for `special[.rG]`.
    @inline(__always)
    private var rG: Int {
        get { Int(truncatingIfNeeded: readSpecial(.rG)) }
        set { writeSpecial(.init(UInt64(bitPattern: .init(newValue))), to: .rG)}
    }

    /// Register stack (for procedure calls).
    private var memoryStack: [Octa]

    // ===== α/β/γ (ring pointers) =====
    // α = start of current frame’s locals
    // β = just past the end (α + rL)
    // γ = start of the “older-but-still-resident” tail (oldest locals not yet
    // spilled to memory)
    //
    // We store α and γ *implicitly* via rO and rS:
    //   α = (rO / 8) mod 256
    //   β = (α + rL) mod 256
    //   γ = (rS / 8) mod 256
    //
    // The invariants:
    //   - Growing rL may require SPILLs while (β == γ) would occur.
    //   - Shrinking/moving α backward may require FILLs while α would cross γ.

    /// Start of current frame's locals within the register ring.
    @inline(__always)
    private var alpha: Int  { (rO >> 3) & 0xFF }

    /// Past-end of current frame's local window (α + `rL`).
    @inline(__always)
    private var beta: Int   { (alpha &+ rL) & 0xFF }

    /// Start of oldest resident local registers not yet spilled.
    @inline(__always)
    private var gamma: Int  { (rS >> 3) & 0xFF }

    // MARK: Initialization

    public init(L: Int = 0, G: Int = 255) {
        precondition(L <= G, "L must be <= G")

        self.general = .init(repeating: .zero, count: 256)
        self.special = .init(repeating: .zero)
        self.memoryStack = []
        self.rL = L
        self.rG = G
    }


    // MARK: Physical/Logical Register Mappings

    /// Map logical local index i (`0 <= i < rL`) to physical register.
    @inline(__always)
    private func physical(for logical: Int) -> Int {
        precondition(logical >= 0 && logical < 256, "logical index out of range")
        if logical < rG {
            return (alpha &+ logical) & 0xFF
        } else {
            // Globals are at fixed indices
            return logical
        }
    }

    @inline(__always)
    private func isLocal(_ i: Int) -> Bool { i < rL }
    @inline(__always)
    private func isMarginal(_ i: Int) -> Bool { i >= rL && i < rG }
    @inline(__always)
    private func isGlobal(_ i: Int) -> Bool { i >= rG }


    // MARK: Register Stack Spills

    /// Spill a single register onto the stack.
    private mutating func spillOne() {
        // Spill l[γ] -> memory at rS, then advance rS (γ := γ + 1)
        memoryStack.append(general[gamma])
        rS &+= 8
    }

    /// Fill one register from the stack.
    private mutating func fillOne() {
        precondition(!memoryStack.isEmpty, "register stack underflow")

        // Move pointer back to point at fill destination
        rS &-= 8
        // Fill that register by popping from the stack
        general[gamma] = memoryStack.removeLast()
    }

    /// Ensure we have room to grow the locals window, spilling as needed.
    private mutating func ensureCapacityForGrowth(by delta: Int) {
        precondition(delta >= 0)
        for _ in 0 ..< delta {
            // avoid β == γ
            if beta == gamma { spillOne() }
            // grow window by 1 (β :=  + 1)
            rL &+= 1
        }
    }

    /// Move the window location (α) backward, filling as needed.
    ///
    /// Typically used during `POP` instructions.
    private mutating func moveAlphaBackward(by delta: Int) {
        precondition(delta >= 0)
        for _ in 0 ..< delta {
            // avoid α crossing γ
            if alpha == gamma { fillOne() }
            // α := α - 1
            rO &-= 8
        }
    }

    // MARK: General Register Access

    @inline(__always)
    private func readPhys(_ i: Int) -> Octa {
        i == 0 ? .zero : general[i]
    }

    @inline(__always)
    private mutating func writePhys(_ v: Octa, _ i: Int) {
        guard i != 0 else { return }
        general[i] = v
    }

    /// Read general register.
    ///
    /// ### Critical Behavior
    ///
    /// - `$0` always returns `0`
    /// - `i < L`: return register value (local)
    /// - `L <= i < G`: return `0` (marginal)
    /// - `i >= G`: return register value (global)
    public func readGeneral(_ index: Int) -> Octa {
        precondition(index >= 0 && index < 256)
        return isMarginal(index) ? .zero : readPhys(physical(for: index))
    }

    /// Write general register.
    ///
    /// ### Critical Behavior
    ///
    /// - `$0` writes are ignored
    /// - `i < L`: write to register (local)
    /// - `L <= i < G`: grow L, clear intervening registers, write
    /// - `i >= G`: write to register (global)
    public mutating func writeGeneral(_ value: Octa, to index: Int) {
        precondition(index >= 0 && index < 256)

        if isMarginal(index) {
            // Promote up to (and including) index
            let delta = (index - rL) + 1
            ensureCapacityForGrowth(by: delta)
            // After growth, $index is local; fall through to write it
        }

        // locals or globals write directly
        writePhys(value, physical(for: index))
    }

    // MARK: Special Registers

    /// Special register identifiers.
    public enum SpecialRegister: Int, CaseIterable, Sendable {
        // Core set
        case rB  = 0
        case rD  = 1
        case rE  = 2
        case rH  = 3
        case rJ  = 4
        case rM  = 5
        case rR  = 6
        case rBB = 7
        case rC  = 8
        case rN  = 9
        case rO  = 10
        case rS  = 11
        case rI  = 12
        case rT  = 13
        case rTT = 14
        case rK  = 15
        case rQ  = 16
        case rU  = 17
        case rV  = 18
        case rG  = 19
        case rL  = 20
        case rA  = 21
        case rF  = 22
        case rP  = 23

        // Trip-path (user) set
        case rW  = 24
        case rX  = 25
        case rY  = 26
        case rZ  = 27

        // Trap-path (kernel) set
        case rWW = 28
        case rXX = 29
        case rYY = 30
        case rZZ = 31

        /// Human-friendly label (optional)
        public var label: String {
            switch self {
            case .rA: return "Arithmetic status"
            case .rB: return "Bootstrap (trip)"
            case .rC: return "Continuation"
            case .rD: return "Dividend"
            case .rE: return "Epsilon"
            case .rF: return "Failure location"
            case .rG: return "Global threshold"
            case .rH: return "Himult"
            case .rI: return "Interval counter"
            case .rJ: return "Return-jump"
            case .rK: return "Interrupt mask"
            case .rL: return "Local threshold"
            case .rM: return "Multiplex mask"
            case .rN: return "Serial number"
            case .rO: return "Register stack offset"
            case .rP: return "Prediction"
            case .rQ: return "Interrupt request"
            case .rR: return "Remainder"
            case .rS: return "Register stack pointer"
            case .rT: return "Trap address"
            case .rU: return "Usage counter"
            case .rV: return "Virtual translation"
            case .rW: return "Where-interrupted (trip)"
            case .rX: return "Execution (trip)"
            case .rY: return "Y operand (trip)"
            case .rZ: return "Z operand (trip)"
            case .rBB: return "Bootstrap (trap)"
            case .rTT: return "Dynamic trap address"
            case .rWW: return "Where-interrupted (trap)"
            case .rXX: return "Execution (trap)"
            case .rYY: return "Y operand (trap)"
            case .rZZ: return "Z operand (trap)"
            }
        }

        public var description: String {
            switch self {
            case .rA: return "rA (\(label))"
            case .rB: return "rB (\(label))"
            case .rC: return "rC (\(label))"
            case .rD: return "rD (\(label))"
            case .rE: return "rE (\(label))"
            case .rF: return "rF (\(label))"
            case .rG: return "rG (\(label))"
            case .rH: return "rH (\(label))"
            case .rI: return "rI (\(label))"
            case .rJ: return "rJ (\(label))"
            case .rK: return "rK (\(label))"
            case .rL: return "rL (\(label))"
            case .rM: return "rM (\(label))"
            case .rN: return "rN (\(label))"
            case .rO: return "rO (\(label))"
            case .rP: return "rP (\(label))"
            case .rQ: return "rQ (\(label))"
            case .rR: return "rR (\(label))"
            case .rS: return "rS (\(label))"
            case .rT: return "rT (\(label))"
            case .rU: return "rU (\(label))"
            case .rV: return "rV (\(label))"
            case .rW: return "rW (\(label))"
            case .rX: return "rX (\(label))"
            case .rY: return "rY (\(label))"
            case .rZ: return "rZ (\(label))"
            case .rBB: return "rBB (\(label))"
            case .rTT: return "rTT (\(label))"
            case .rWW: return "rWW (\(label))"
            case .rXX: return "rXX (\(label))"
            case .rYY: return "rYY (\(label))"
            case .rZZ: return "rZZ (\(label))"
            }
        }
    }

    /// Read special register.
    public func readSpecial(_ register: SpecialRegister) -> Octa {
        special[register.rawValue]
    }

    /// Write special register.
    ///
    /// - Important: Some registers have side-effects.
    public mutating func writeSpecial(
        _ value: Octa, to register: SpecialRegister
    ) {
        special[register.rawValue] = value
        switch register {
        case .rS:
            // Ensure memory stack size matches; instructions can technically
            // overwrite this value directly.
            let want = Int(truncatingIfNeeded: value.storage) >> 3
            if want > memoryStack.count {
                // extend with zeroes (zero-fill makes for nicer visualization)
                memoryStack.append(
                    contentsOf: repeatElement(
                        .zero, count: want - memoryStack.count))
            } else if want < memoryStack.count {
                // trim the memory region; we use append/removeLast, so we will
                // trim to ensure those continue to work as expected, rather
                // than eliding the trim and just ignoring the values.
                // Swift will likely elide the trim internally if it's small
                // enough.
                memoryStack.removeLast(memoryStack.count - want)
            }
        default:
            break
        }
    }

    // MARK: Register Stack Operations

    /// Slides the register window forward past the current frame's locals.
    ///
    /// - Returns: Number of locals on the stack frame being replaced.
    public mutating func pushFrame() -> Int {
        let result = rL
        rO &+= rL &* 8
        return result
    }

    /// Pop the given frame, restoring a previous rL value.
    ///
    /// - Parameters:
    ///   - previousL: Number of local variables on the prior stack frame.
    public mutating func popFrame(ofSize size: Int) {
        // If the callee still has locals, shrink them first (no fill/spill).
        if rL > 0 {
            rL = 0
        }

        // Slide window backward; this may fill from the stack.
        moveAlphaBackward(by: size)

        // Restore the caller's local register count.
        rL = size
    }


    // MARK: Debugging/Visualization Aids

    /// Get all local registers (for debugging).
    public var locals: [Octa] {
        if alpha < beta {
            Array(general[alpha..<beta])
        } else {
            Array(general[alpha..<rG]) + Array(general[..<beta])
        }
    }

    /// Get all global registers (for debugging).
    public var globals: [Octa] {
        Array(general[rG...])
    }

    /// Get general register information (for debugging/visualization).
    public var generalRegisters: ([Octa], O: Int, L: Int, G: Int) {
        (.init(general), rO, rL, rG)
    }
}

// MARK: - MachineKit Protocol Conformance

extension MMIXRegisterFile: RegisterFile {
    public typealias Word = Octa

    public enum RegisterIdentifier: Hashable, Sendable {
        case general(Int)
        case special(SpecialRegister)
    }

    public func read(_ register: RegisterIdentifier) -> Octa {
        switch register {
        case .general(let index):
            return readGeneral(index)
        case .special(let special):
            return readSpecial(special)
        }
    }

    public mutating func write(_ value: Octa, to register: RegisterIdentifier) {
        switch register {
        case .general(let index):
            writeGeneral(value, to: index)
        case .special(let special):
            writeSpecial(value, to: special)
        }
    }
}
