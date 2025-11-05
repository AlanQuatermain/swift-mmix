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
    private var rO: Int {
        get { Int(truncatingIfNeeded: readSpecial(.rO)) }
        set { writeSpecial(.init(UInt64(bitPattern: .init(newValue))), to: .rO) }
    }

    /// Register stack pointer - total octabytes in memory stack.
    ///
    /// This is just a quick accessor/converter for `special[.rS]`.
    private var rS: Int {
        get { Int(truncatingIfNeeded: readSpecial(.rS)) }
        set { writeSpecial(.init(UInt64(bitPattern: .init(newValue))), to: .rS) }
    }

    /// Local register threshold.
    ///
    /// This is just a quick accessor/converter for `special[.rL]`.
    public private(set) var rL: Int {
        get { Int(truncatingIfNeeded: readSpecial(.rL)) }
        set { writeSpecial(.init(UInt64(bitPattern: .init(newValue))), to: .rL) }
    }

    /// Global register threshold.
    ///
    /// This is just a quick accessor/converter for `special[.rG]`.
    public private(set) var rG: Int {
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
    private var alpha: Int  { (rO >> 3) & 0xFF }

    /// Past-end of current frame's local window (α + `rL`).
    private var beta: Int   { (alpha &+ rL) & 0xFF }

    /// Start of oldest resident local registers not yet spilled.
    private var gamma: Int  { (rS >> 3) & 0xFF }

    // MARK: Initialization

    public init(L: Int = 0, G: Int = 255) {
        precondition(L <= G, "L must be <= G")

        self.general = .init(repeating: .zero, count: 256)
        self.special = .init(repeating: .zero)
        self.rL = L
        self.rG = G
        self.memoryStack = []
    }


    // MARK: Physical/Logical Register Mappings

    /// Map logical local index i (`0 <= i < rL`) to physical register.
    private func physical(for local: Int) -> Int {
        precondition(local >= 0 && local < rL, "local index out of range")
        return (alpha &+ local) & 0xFF
    }


    // MARK: Register Stack Spills

    /// Check if pushing would require spilling registers.
    private func needsSpill(pushingBy count: Int) -> Bool {
        let newRO = (rO + count) % rG

        // Active region: [rO, rO + L]
        let activeStart = rO
        let activeEnd = (rO + rL) % rG

        func rangesOverlap(s1: Int, l1: Int, s2: Int, l2: Int, m: Int) -> Bool {
            let e1 = (s1 + l1) % m
            let e2 = (s2 + l2) % m

            // Handle wraparound cases
            if s1 <= e1 && s2 <= e2 {
                // Neither wraps
                return !(e1 <= s2 || e2 <= s1)
            }
            else if s1 > e1 && s2 > e2 {
                // Both wrap -- they must overlap
                return true
            }
            else if s1 > e1 {
                // First range wraps.
                // Range 1 occupies [s1, m) and [0, e1).
                // Gap is [e1, s1).
                // They overlap if range 2 is not ENTIRELY within that gap
                return !(s2 >= e1 && e2 <= s1)
            }
            else {
                // Second range wraps.
                // Range 2 occupies [s2, m) and [0, e2).
                // Gap is [e2, s2).
                // They overlap if range 1 is not ENTIRELY within that gap
                return !(s1 >= e2 && e1 <= s2)
            }
        }

        // Check if new frame position would overlap with active region.
        // This requires checking circular range overlap.
        return rangesOverlap(
            s1: newRO, l1: count, s2: activeStart, l2: Int(L), m: Int(G))
    }


    // MARK: General Register Access

    /// Read general register.
    ///
    /// ### Critical Behavior
    ///
    /// - `$0` always returns `0`
    /// - `i < L`: return register value (local)
    /// - `L <= i < G`: return `0` (marginal)
    /// - `i >= G`: return register value (global)
    public func readGeneral(_ index: Int) -> Octa {
        precondition(index < 256)
        guard index != 0 else { return .zero }

        if index < L || index >= G {
            return general[index]
        } else {
            // Marginal register reads as zero.
            return .zero
        }
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
        precondition(index < 256)
        guard index != 0 else { return }

        if index < L {
            // Local register - direct write
            general[index] = value
        }
        else if index < G {
            // Writing marginal register grows L.
            // Clear all registers from old L through index.
            for i in Int(L)..<index {
                general[i] = .zero
            }
            general[index] = value
            L = UInt8(index + 1)

            // Update rL special register.
            writeSpecial(Octa(UInt64(L)), to: .rL)
        }
        else {
            // Global register - direct write
            general[index] = value
        }
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

        // Handle side effects
        switch register {
        case .rL:
            L = UInt8(truncatingIfNeeded: value.storage)
        case .rG:
            G = UInt8(truncatingIfNeeded: value.storage)
        case .rS:
            stackPointer = Int(value.storage)
        default:
            break
        }
    }

    // MARK: Register Stack Operations

    /// PUSH operation (for `PUSHJ`/`PUSHGO`).
    ///
    /// Shifts the local register window by the specified number of arguments.
    public mutating func push(argumentCount: Int) {
        precondition(
            argumentCount >= 0 && argumentCount <= Int(L),
            "Invalid argument count: \(argumentCount)")

        // Save registers from 0 to L-1 (excluding arguments)
        let saveCount = Int(L) - argumentCount
        let newRO = (rO + saveCount) % Int(G)

        // Check if we need to spill to memory.
        if needsSpill(pushingBy: saveCount) {
            // Calculate how many registers to spill
            let spillCount = calculateSpillCount(
                newRO: newRO, argumentCount: argumentCount)
        }
    }

    /// POP operation (for `POP` instruction)
    ///
    /// Restores local registers from stack.  Returns register count restored.
    public mutating func pop(returnValueCount: Int = 0) -> Int {
        // Determine how many to restore
        let offset = Int(readSpecial(.rO).storage)
        let restoreCount = min(stackPointer, 256 - offset)
        guard restoreCount > 0 else {
            L = UInt8(returnValueCount)
            return 0
        }

        // Restore from stack
        let startIndex = stack.count - restoreCount
        let restored = stack[startIndex...]
        for (i, value) in restored.enumerated() {
            general[returnValueCount + i] = value
        }

        stack.removeLast(restoreCount)
        stackPointer -= restoreCount

        L = UInt8(returnValueCount + restoreCount)

        // Update special registers
        special[SpecialRegister.rO.rawValue] = .zero
        special[SpecialRegister.rS.rawValue] = Octa(UInt64(stackPointer))

        return restoreCount
    }

    /// Get all local registers (for debugging).
    public var locals: [Octa] {
        Array(general[..<Int(L)])
    }

    /// Get all global registers (for debugging).
    public var globals: [Octa] {
        Array(general[Int(G)...])
    }

    /// Get general register information (for debugging/visualization).
    public var generalRegisters: ([Octa], L: Int, G: Int) {
        (general, Int(L), Int(G))
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
