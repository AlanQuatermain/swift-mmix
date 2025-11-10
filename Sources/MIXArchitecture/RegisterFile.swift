//
//  RegisterFile.swift
//  swift-mmix
//
//  Created by Jim Dovey on 10/13/25.
//

import MachineKit

/// MIX Register File
///
/// ### Components
///
/// - `A` (Accumulator): 5 bytes + sign
/// - `X` (Extension): 5 bytes + sign
/// - `I1`–`I6` (Index): 2 bytes + sign each
/// - `J` (Jump): 2 bytes, unsigned (0-4095)
/// - Overflow toggle (boolean flag)
/// - Comparison indicator (ternary: `<`, `=`, `>`)
public struct MIXRegisterFile: Sendable {
    // MARK: Registers

    /// Accumulator.
    public var A: MIXWord

    /// Extension register (pairs with `A` for 10-byte operations).
    public var X: MIXWord

    /// Index registers (2 bytes + sign each).
    private var indexRegisters: [MIXWord]    // 6 elements

    /// Jump register (2 bytes, unsigned)
    public var J: MIXAddress

    /// Overflow toggle.
    ///
    /// Set by arithmetic overflow, cleared by specific instructions.
    public var overflowToggle: Bool

    /// Comparison indicator.
    ///
    /// Set by `CMPA`, `CMPX`, `CMPi` instructions.
    public var comparisonIndicator: ComparisonResult

    // MARK: Initialization

    public init() {
        A = .positiveZero
        X = .positiveZero
        indexRegisters = Array(repeating: .positiveZero, count: 6)
        J = MIXAddress(0)
        overflowToggle = false
        comparisonIndicator = .equal
    }

    // MARK: Index Register Access

    /// Read index register (1...6).
    public func readIndex(_ index: Int) -> MIXWord {
        precondition((1...6).contains(index), "Index register must be 1...6")
        return indexRegisters[index-1]
    }

    /// Write index register (1...6).
    ///
    /// Indexes only contain 2 bytes + sign. Values are truncated using the
    /// address field (bytes 4:5).
    public mutating func writeIndex(_ value: MIXWord, to index: Int) {
        precondition((1...6).contains(index), "Index register must be 1...6")
        indexRegisters[index - 1] = value.addressField
    }

    // MARK: Effective Address Calculation

    /// Compute effective address with indexing.
    ///
    ///     EA = (base address) + (index register value) mod 4000
    ///
    /// - `index=0` means no indexing
    /// - Index register value is signed
    /// - Result wraps to 12-bit address (0–4095)
    public func effectiveAddress(base: MIXAddress, index: Int) -> MIXAddress {
        precondition((0...6).contains(index), "Index register must be 1...6")

        guard index != 0 else { return base }

        let indexValue = readIndex(index)
        let indexAddr = indexValue.signedValue

        // Compute EA with wrapping
        let ea = Int(base.value) + Int(indexAddr)

        // MIX can address 4000 words
        var wrapped = ea % 4000
        if wrapped < 0 {
            wrapped += 4000
        }
        return MIXAddress(UInt16(wrapped))
    }

    /// Get index register as address offset.
    ///
    /// Returns signed offset suitable for address arithmetic.
    public func indexOffset(_ index: Int) -> Int {
        guard index >= 1 && index <= 6 else { return 0 }
        return Int(readIndex(index).signedValue)
    }
}

// MARK: - MachineKit Protocol Conformance

extension MIXRegisterFile: RegisterFile {
    public typealias Word = MIXWord

    public enum RegisterIdentifier: Hashable, Sendable {
        case A
        case X
        case index(Int) // 1...6
        case J
    }

    public func read(_ register: RegisterIdentifier) -> MIXWord {
        switch register {
        case .A: A
        case .X: X
        case .index(let i): readIndex(i)
        case .J: J.asWord
        }
    }

    public mutating func write(_ value: MIXWord, to register: RegisterIdentifier) {
        switch register {
        case .A: A = value
        case .X: X = value
        case .index(let i): writeIndex(value, to: i)
        case .J: J = MIXAddress(fromWord: value)
        }
    }
}

// MARK: - Debugging Support

extension MIXRegisterFile: CustomStringConvertible {
    public var description: String {
        """
        A: \(A)
        X: \(X)
        I1: \(indexRegisters[0]) I2: \(indexRegisters[1]) I3: \(indexRegisters[2])
        I4: \(indexRegisters[3]) I5: \(indexRegisters[4]) I6: \(indexRegisters[5])
        J: \(J)
        OV: \(overflowToggle) CMP: \(comparisonIndicator)
        """
    }
}
