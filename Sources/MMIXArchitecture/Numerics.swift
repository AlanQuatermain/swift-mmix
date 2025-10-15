//
//  Numerics.swift
//  swift-mmix
//
//  Created by Jim Dovey on 10/12/25.
//

import MachineKit

/// MMIX Octa - 64-bit unsigned word (primary register width)
///
/// Represents an 8-byte value using 2's-complement arithmetic.
/// While storage is unsigned, MMIX instructions interpret values as signed
/// or unsigned depending on the opcode.
public struct Octa: Sendable, Hashable, Codable {
    /// Underlying 64-bit unsigned storage.
    public var storage: UInt64

    /// Create from an unsigned value.
    /// - parameter value: The 64-bit quantity to use.
    public init(_ value: UInt64) {
        storage = value
    }

    /// Initialize with any integer type, truncating if needed.
    /// - parameter value: A binary integer.
    public init(truncatingIfNeeded value: some BinaryInteger) {
        storage = .init(truncatingIfNeeded: value)
    }

    /// Initialize truncating bits from another integer type.
    /// Required by FixedWidthInteger protocol.
    /// - parameter source: The source value to truncate.
    public init(_truncatingBits source: UInt) {
        storage = UInt64(truncatingIfNeeded: source)
    }

    /// Two's-complement signed interpretation.
    ///
    /// - Note: Many MMIX instructions (`CMP`, `ADDU` vs `ADD`, etc.) need both
    ///   signed and unsigned views of the same bits.
    public var asSigned: Int64 {
        Int64(bitPattern: storage)
    }

    /// Create from a two's-complement signed value.
    /// - parameter value: The signed quantity to use.
    public init(signed value: Int64) {
        storage = .init(bitPattern: value)
    }

    /// Zero constant.
    public static let zero = Octa(0)

    /// Maximum value.
    public static let max = Octa(UInt64.max)
}

// MARK: - Multi-byte decomposition (big-endian)

extension Octa {
    /// Extract high tetra (bits 63–32).
    public var highTetra: Tetra {
        Tetra(UInt32(truncatingIfNeeded: storage >> 32))
    }

    /// Extract low tetra (bits 31–0).
    public var lowTetra: Tetra {
        Tetra(UInt32(truncatingIfNeeded: storage & 0xFFFF_FFFF))
    }

    /// Construct from two tetras (big-endian: high || low).
    ///
    /// - parameters:
    ///   - high: High 32-bit tetra.
    ///   - low: Low 32-bit tetra.
    public init(high: Tetra, low: Tetra) {
        storage = UInt64(high.storage) << 32 | UInt64(low.storage)
    }

    /// Extract byte at position (0 = most significant).
    ///
    /// MMIX is big-endian: byte 0 is bits 63–56.
    /// - parameter position: Location of byte to extract.
    public subscript(position: Int) -> Byte {
        precondition (0...7 ~= position, "Byte index out of range")
        let shift = (7 - position) * 8
        return Byte(UInt8(truncatingIfNeeded: storage >> shift))
    }

    /// Construct from 8 bytes in big-endian order.
    ///
    /// - parameter bytes: The bytes to use, starting with most-significant.
    public init(bytes: [Byte]) {
        precondition(bytes.count == 8, "Octa requires exactly 8 bytes")
        if let value = bytes.withContiguousStorageIfAvailable({ bufPtr in
            bufPtr.withMemoryRebound(to: UInt64.self) { $0[0] }
        }) {
            storage = value.bigEndian
        }
        else {
            var result: UInt64 = 0
            for (index, byte) in bytes.enumerated() {
                let shift = (7 - index) * 8
                result |= (UInt64(byte.storage) << shift)
            }
            storage = result
        }
    }

    /// Byte-array access in big-endian order.
    public var bytes: [Byte] {
        (0..<8).map { self[$0] }
    }

    /// Initialize using a collection of raw bytes.
    ///
    /// - Note: This is explicitly a slow-path implementation, intended for use
    ///   when reading unaligned values.
    public init<C: Collection>(bytes: C) where C.Element == Byte, C.Index == Int {
        let value = (UInt64(bytes[0]) << 56) | (UInt64(bytes[1]) << 48)
            | (UInt64(bytes[2]) << 40) | (UInt64(bytes[3]) << 32)
            | (UInt64(bytes[4]) << 24) | (UInt64(bytes[5]) << 16)
            | (UInt64(bytes[6]) << 8) | (UInt64(bytes[7]))
        self.init(value)
    }
}

// MARK: - Octa Arithmetic Operations

extension Octa {
    /// Signed comparison (for `CMP` instruction).
    public func signedCompare(to other: Octa) -> ComparisonResult {
        let a = self.asSigned
        let b = other.asSigned
        if a < b { return .less }
        if a > b { return .greater }
        return .equal
    }

    /// Unsigned comparison (for `CMPU` instruction).
    public func unsignedCompare(to other: Octa) -> ComparisonResult {
        if storage < other.storage { return .less }
        if storage > other.storage { return .greater }
        return .equal
    }

    /// Add with overflow detection.
    ///
    /// Used with `ADD` instruction which traps on overflow.
    public func addingReportingOverflow(_ other: Octa) -> (partialValue: Octa, overflow: Bool) {
        let (result, overflow) = storage.addingReportingOverflow(other.storage)
        return (.init(result), overflow)
    }

    /// Signed addition with overflow detection.
    ///
    /// For instructions that trap on signed overflow.
    public func signedAddingReportingOverflow(_ other: Octa) -> (partialValue: Octa, overflow: Bool) {
        let (result, overflow) = asSigned.addingReportingOverflow(other.asSigned)
        return (.init(signed: result), overflow)
    }

    /// Multiply returning high and low words.
    ///
    /// - Note: MMIX `MUL` instruction stores low word in destination, high word
    ///   in `rH` special register.
    public func multipliedFullWidth(by other: Octa) -> (high: Octa, low: Octa) {
        let result = storage.multipliedFullWidth(by: other.storage)
        return (Octa(result.high), Octa(result.low))
    }

    /// Division with remainder.
    ///
    /// - Note: `DIV` stores quotient in destination, remainder in `rR`.
    public func quotientAndRemainder(dividingBy other: Octa) -> (quotient: Octa, remainder: Octa) {
        guard other.storage != 0 else {
            // Divide by zero -- caller should trap
            return (.zero, self)
        }
        let (quotient, remainder) = storage.quotientAndRemainder(dividingBy: other.storage)
        return (Octa(quotient), Octa(remainder))
    }
}

// MARK: - Octa Protocol Conformance

extension Octa: FixedWidthInteger, UnsignedInteger {
    public static var bitWidth: Int { 64 }
    public static var isSigned: Bool { false }
    public static var min: Octa { .zero }

    // MARK: - BinaryInteger Requirements
    
    public var words: [UInt] {
        #if arch(x86_64) || arch(arm64)
        return [UInt(storage)]
        #else
        return [UInt(storage & 0xFFFF_FFFF), UInt(storage >> 32)]
        #endif
    }
    
    public var trailingZeroBitCount: Int {
        storage.trailingZeroBitCount
    }
    
    public static func / (lhs: Octa, rhs: Octa) -> Octa {
        .init(lhs.storage / rhs.storage)
    }
    
    public static func /= (lhs: inout Octa, rhs: Octa) {
        lhs = lhs / rhs
    }
    
    public static func % (lhs: Octa, rhs: Octa) -> Octa {
        .init(lhs.storage % rhs.storage)
    }
    
    public static func %= (lhs: inout Octa, rhs: Octa) {
        lhs = lhs % rhs
    }
    
    // MARK: - Numeric Requirements
    
    public var magnitude: Octa { self }
    
    public init?<T>(exactly source: T) where T : BinaryInteger {
        guard let value = UInt64(exactly: source) else { return nil }
        self.init(value)
    }
    
    // MARK: - FixedWidthInteger Requirements
    
    public static func &+ (lhs: Octa, rhs: Octa) -> Octa {
        .init(lhs.storage &+ rhs.storage)
    }
    
    public static func &+= (lhs: inout Octa, rhs: Octa) {
        lhs = lhs &+ rhs
    }
    
    public static func &- (lhs: Octa, rhs: Octa) -> Octa {
        .init(lhs.storage &- rhs.storage)
    }
    
    public static func &-= (lhs: inout Octa, rhs: Octa) {
        lhs = lhs &- rhs
    }
    
    public static func &* (lhs: Octa, rhs: Octa) -> Octa {
        .init(lhs.storage &* rhs.storage)
    }
    
    public static func &*= (lhs: inout Octa, rhs: Octa) {
        lhs = lhs &* rhs
    }
    
    public static func &<< (lhs: Octa, rhs: some BinaryInteger) -> Octa {
        .init(lhs.storage &<< rhs)
    }
    
    public static func &<<= (lhs: inout Octa, rhs: some BinaryInteger) {
        lhs = lhs &<< rhs
    }
    
    public static func &>> (lhs: Octa, rhs: some BinaryInteger) -> Octa {
        .init(lhs.storage &>> rhs)
    }
    
    public static func &>>= (lhs: inout Octa, rhs: some BinaryInteger) {
        lhs = lhs &>> rhs
    }
    
    public init(clamping source: some BinaryInteger) {
        if source < 0 {
            self = .zero
        } else if source > UInt64.max {
            self = .max
        } else {
            self.init(UInt64(source))
        }
    }
    
    public func subtractingReportingOverflow(_ rhs: Octa) -> (partialValue: Octa, overflow: Bool) {
        let (result, overflow) = storage.subtractingReportingOverflow(rhs.storage)
        return (.init(result), overflow)
    }
    
    public func multipliedReportingOverflow(by rhs: Octa) -> (partialValue: Octa, overflow: Bool) {
        let (result, overflow) = storage.multipliedReportingOverflow(by: rhs.storage)
        return (.init(result), overflow)
    }
    
    public func dividedReportingOverflow(by rhs: Octa) -> (partialValue: Octa, overflow: Bool) {
        guard rhs.storage != 0 else {
            return (self, true)
        }
        let (result, overflow) = storage.dividedReportingOverflow(by: rhs.storage)
        return (.init(result), overflow)
    }
    
    public func remainderReportingOverflow(dividingBy rhs: Octa) -> (partialValue: Octa, overflow: Bool) {
        guard rhs.storage != 0 else {
            return (self, true)
        }
        let (result, overflow) = storage.remainderReportingOverflow(dividingBy: rhs.storage)
        return (.init(result), overflow)
    }
    
    public func dividingFullWidth(_ dividend: (high: Octa, low: Octa)) -> (quotient: Octa, remainder: Octa) {
        let (quotient, remainder) = storage.dividingFullWidth((dividend.high.storage, dividend.low.storage))
        return (Octa(quotient), Octa(remainder))
    }
    
    public var nonzeroBitCount: Int {
        storage.nonzeroBitCount
    }
    
    public var leadingZeroBitCount: Int {
        storage.leadingZeroBitCount
    }
    
    public var byteSwapped: Octa {
        .init(storage.byteSwapped)
    }

    // MARK: - Arithmetic Operators (use wrapping semantics)

    public static func + (lhs: Octa, rhs: Octa) -> Octa {
        .init(lhs.storage &+ rhs.storage)
    }

    public static func += (lhs: inout Octa, rhs: Octa) {
        lhs = lhs + rhs
    }

    public static func - (lhs: Octa, rhs: Octa) -> Octa {
        .init(lhs.storage &- rhs.storage)
    }

    public static func -= (lhs: inout Octa, rhs: Octa) {
        lhs = lhs - rhs
    }

    public static func * (lhs: Octa, rhs: Octa) -> Octa {
        .init(lhs.storage &* rhs.storage)
    }

    public static func *= (lhs: inout Octa, rhs: Octa) {
        lhs = lhs * rhs
    }

    // MARK: - Bitwise Operators

    public static func & (lhs: Octa, rhs: Octa) -> Octa {
        .init(lhs.storage & rhs.storage)
    }

    public static func &= (lhs: inout Octa, rhs: Octa) {
        lhs = lhs & rhs
    }

    public static func | (lhs: Octa, rhs: Octa) -> Octa {
        .init(lhs.storage | rhs.storage)
    }

    public static func |= (lhs: inout Octa, rhs: Octa) {
        lhs = lhs | rhs
    }

    public static func ^ (lhs: Octa, rhs: Octa) -> Octa {
        .init(lhs.storage ^ rhs.storage)
    }

    public static func ^= (lhs: inout Octa, rhs: Octa) {
        lhs = lhs ^ rhs
    }

    public static prefix func ~ (operand: Octa) -> Octa {
        .init(~operand.storage)
    }

    // MARK: - Shift Operators

    public static func << (lhs: Octa, rhs: some BinaryInteger) -> Octa {
        .init(lhs.storage << rhs)
    }

    public static func <<= (lhs: inout Octa, rhs: some BinaryInteger) {
        lhs = lhs << rhs
    }

    public static func >> (lhs: Octa, rhs: some BinaryInteger) -> Octa {
        .init(lhs.storage >> rhs)
    }

    public static func >>= (lhs: inout Octa, rhs: some BinaryInteger) {
        lhs = lhs >> rhs
    }

    // MARK: - Comparison

    public static func < (lhs: Octa, rhs: Octa) -> Bool {
        lhs.storage < rhs.storage
    }

    // MARK: - Integer literal

    public init(integerLiteral value: UInt64) {
        storage = value
    }
}

// MARK: -

/// MMIX Tetra - 32-bit unsigned value (four bytes)
///
/// Represents a 4-byte value using 2's-complement arithmetic.
/// While storage is unsigned, MMIX instructions interpret values as signed
/// or unsigned depending on the opcode.
public struct Tetra: Sendable, Hashable, Codable {
    /// Underlying 32-bit unsigned storage.
    public var storage: UInt32

    /// Create from an unsigned value.
    /// - parameter value: The 32-bit quantity to use.
    public init(_ value: UInt32) {
        storage = value
    }

    /// Initialize with any integer type, truncating if needed.
    /// - parameter value: A binary integer.
    public init(truncatingIfNeeded value: some BinaryInteger) {
        storage = .init(truncatingIfNeeded: value)
    }

    /// Initialize truncating bits from another integer type.
    /// Required by FixedWidthInteger protocol.
    /// - parameter source: The source value to truncate.
    public init(_truncatingBits source: UInt) {
        storage = UInt32(truncatingIfNeeded: source)
    }

    /// Two's-complement signed interpretation.
    ///
    /// - Note: Many MMIX instructions need both signed and unsigned views of the same bits.
    public var asSigned: Int32 {
        Int32(bitPattern: storage)
    }

    /// Create from a two's-complement signed value.
    /// - parameter value: The signed quantity to use.
    public init(signed value: Int32) {
        storage = .init(bitPattern: value)
    }

    /// Zero constant.
    public static let zero = Tetra(0)

    /// Maximum value.
    public static let max = Tetra(UInt32.max)
}

// MARK: - Tetra Multi-wyde decomposition (big-endian)

extension Tetra {
    /// Extract high wyde (bits 31–16).
    public var highWyde: Wyde {
        Wyde(UInt16(truncatingIfNeeded: storage >> 16))
    }

    /// Extract low wyde (bits 15–0).
    public var lowWyde: Wyde {
        Wyde(UInt16(truncatingIfNeeded: storage & 0xFFFF))
    }

    /// Construct from two wydes (big-endian: high || low).
    ///
    /// - parameters:
    ///   - high: High 16-bit wyde.
    ///   - low: Low 16-bit wyde.
    public init(high: Wyde, low: Wyde) {
        storage = UInt32(high.storage) << 16 | UInt32(low.storage)
    }

    /// Get wydes as array [high, low].
    public var wydes: [Wyde] {
        [highWyde, lowWyde]
    }

    /// Get all bytes as array [MSB...LSB] (4 bytes).
    public var bytes: [Byte] {
        [
            Byte(UInt8(truncatingIfNeeded: storage >> 24)),
            Byte(UInt8(truncatingIfNeeded: storage >> 16)),
            Byte(UInt8(truncatingIfNeeded: storage >> 8)),
            Byte(UInt8(truncatingIfNeeded: storage & 0xFF))
        ]
    }

    /// Initialize using a collection of raw bytes.
    ///
    /// - Note: This is explicitly a slow-path implementation, intended for use
    ///   when reading unaligned values.
    public init<C: Collection>(bytes: C) where C.Element == Byte, C.Index == Int {
        let value = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16)
            | (UInt32(bytes[2]) << 8) | (UInt32(bytes[3]))
        self.init(value)
    }
}

// MARK: - Tetra Arithmetic Operations

extension Tetra {
    /// Signed comparison.
    public func signedCompare(to other: Tetra) -> ComparisonResult {
        let a = self.asSigned
        let b = other.asSigned
        if a < b { return .less }
        if a > b { return .greater }
        return .equal
    }

    /// Unsigned comparison.
    public func unsignedCompare(to other: Tetra) -> ComparisonResult {
        if storage < other.storage { return .less }
        if storage > other.storage { return .greater }
        return .equal
    }

    /// Add with overflow detection.
    public func addingReportingOverflow(_ other: Tetra) -> (partialValue: Tetra, overflow: Bool) {
        let (result, overflow) = storage.addingReportingOverflow(other.storage)
        return (.init(result), overflow)
    }

    /// Signed addition with overflow detection.
    public func signedAddingReportingOverflow(_ other: Tetra) -> (partialValue: Tetra, overflow: Bool) {
        let (result, overflow) = asSigned.addingReportingOverflow(other.asSigned)
        return (.init(signed: result), overflow)
    }

    /// Multiply returning high and low words.
    public func multipliedFullWidth(by other: Tetra) -> (high: Tetra, low: Tetra) {
        let result = storage.multipliedFullWidth(by: other.storage)
        return (Tetra(result.high), Tetra(result.low))
    }

    /// Division with remainder.
    public func quotientAndRemainder(dividingBy other: Tetra) -> (quotient: Tetra, remainder: Tetra) {
        guard other.storage != 0 else {
            return (.zero, self)
        }
        let (quotient, remainder) = storage.quotientAndRemainder(dividingBy: other.storage)
        return (Tetra(quotient), Tetra(remainder))
    }
}

// MARK: - Tetra Protocol Conformance

extension Tetra: FixedWidthInteger, UnsignedInteger {
    public static var bitWidth: Int { 32 }
    public static var isSigned: Bool { false }
    public static var min: Tetra { .zero }

    public var words: [UInt] {
        [UInt(storage)]
    }

    public var trailingZeroBitCount: Int {
        storage.trailingZeroBitCount
    }

    public static func / (lhs: Tetra, rhs: Tetra) -> Tetra {
        .init(lhs.storage / rhs.storage)
    }

    public static func /= (lhs: inout Tetra, rhs: Tetra) {
        lhs = lhs / rhs
    }

    public static func % (lhs: Tetra, rhs: Tetra) -> Tetra {
        .init(lhs.storage % rhs.storage)
    }

    public static func %= (lhs: inout Tetra, rhs: Tetra) {
        lhs = lhs % rhs
    }

    public var magnitude: Tetra { self }

    public init?<T>(exactly source: T) where T : BinaryInteger {
        guard let value = UInt32(exactly: source) else { return nil }
        self.init(value)
    }

    public static func &+ (lhs: Tetra, rhs: Tetra) -> Tetra {
        .init(lhs.storage &+ rhs.storage)
    }

    public static func &+= (lhs: inout Tetra, rhs: Tetra) {
        lhs = lhs &+ rhs
    }

    public static func &- (lhs: Tetra, rhs: Tetra) -> Tetra {
        .init(lhs.storage &- rhs.storage)
    }

    public static func &-= (lhs: inout Tetra, rhs: Tetra) {
        lhs = lhs &- rhs
    }

    public static func &* (lhs: Tetra, rhs: Tetra) -> Tetra {
        .init(lhs.storage &* rhs.storage)
    }

    public static func &*= (lhs: inout Tetra, rhs: Tetra) {
        lhs = lhs &* rhs
    }

    public static func &<< (lhs: Tetra, rhs: some BinaryInteger) -> Tetra {
        .init(lhs.storage &<< rhs)
    }

    public static func &<<= (lhs: inout Tetra, rhs: some BinaryInteger) {
        lhs = lhs &<< rhs
    }

    public static func &>> (lhs: Tetra, rhs: some BinaryInteger) -> Tetra {
        .init(lhs.storage &>> rhs)
    }

    public static func &>>= (lhs: inout Tetra, rhs: some BinaryInteger) {
        lhs = lhs &>> rhs
    }

    public init(clamping source: some BinaryInteger) {
        if source < 0 {
            self = .zero
        } else if source > UInt32.max {
            self = .max
        } else {
            self.init(UInt32(source))
        }
    }

    public func subtractingReportingOverflow(_ rhs: Tetra) -> (partialValue: Tetra, overflow: Bool) {
        let (result, overflow) = storage.subtractingReportingOverflow(rhs.storage)
        return (.init(result), overflow)
    }

    public func multipliedReportingOverflow(by rhs: Tetra) -> (partialValue: Tetra, overflow: Bool) {
        let (result, overflow) = storage.multipliedReportingOverflow(by: rhs.storage)
        return (.init(result), overflow)
    }

    public func dividedReportingOverflow(by rhs: Tetra) -> (partialValue: Tetra, overflow: Bool) {
        guard rhs.storage != 0 else {
            return (self, true)
        }
        let (result, overflow) = storage.dividedReportingOverflow(by: rhs.storage)
        return (.init(result), overflow)
    }

    public func remainderReportingOverflow(dividingBy rhs: Tetra) -> (partialValue: Tetra, overflow: Bool) {
        guard rhs.storage != 0 else {
            return (self, true)
        }
        let (result, overflow) = storage.remainderReportingOverflow(dividingBy: rhs.storage)
        return (.init(result), overflow)
    }

    public func dividingFullWidth(_ dividend: (high: Tetra, low: Tetra)) -> (quotient: Tetra, remainder: Tetra) {
        let (quotient, remainder) = storage.dividingFullWidth((dividend.high.storage, dividend.low.storage))
        return (Tetra(quotient), Tetra(remainder))
    }

    public var nonzeroBitCount: Int {
        storage.nonzeroBitCount
    }

    public var leadingZeroBitCount: Int {
        storage.leadingZeroBitCount
    }

    public var byteSwapped: Tetra {
        .init(storage.byteSwapped)
    }

    public static func + (lhs: Tetra, rhs: Tetra) -> Tetra {
        .init(lhs.storage &+ rhs.storage)
    }

    public static func += (lhs: inout Tetra, rhs: Tetra) {
        lhs = lhs + rhs
    }

    public static func - (lhs: Tetra, rhs: Tetra) -> Tetra {
        .init(lhs.storage &- rhs.storage)
    }

    public static func -= (lhs: inout Tetra, rhs: Tetra) {
        lhs = lhs - rhs
    }

    public static func * (lhs: Tetra, rhs: Tetra) -> Tetra {
        .init(lhs.storage &* rhs.storage)
    }

    public static func *= (lhs: inout Tetra, rhs: Tetra) {
        lhs = lhs * rhs
    }

    public static func & (lhs: Tetra, rhs: Tetra) -> Tetra {
        .init(lhs.storage & rhs.storage)
    }

    public static func &= (lhs: inout Tetra, rhs: Tetra) {
        lhs = lhs & rhs
    }

    public static func | (lhs: Tetra, rhs: Tetra) -> Tetra {
        .init(lhs.storage | rhs.storage)
    }

    public static func |= (lhs: inout Tetra, rhs: Tetra) {
        lhs = lhs | rhs
    }

    public static func ^ (lhs: Tetra, rhs: Tetra) -> Tetra {
        .init(lhs.storage ^ rhs.storage)
    }

    public static func ^= (lhs: inout Tetra, rhs: Tetra) {
        lhs = lhs ^ rhs
    }

    public static prefix func ~ (operand: Tetra) -> Tetra {
        .init(~operand.storage)
    }

    public static func << (lhs: Tetra, rhs: some BinaryInteger) -> Tetra {
        .init(lhs.storage << rhs)
    }

    public static func <<= (lhs: inout Tetra, rhs: some BinaryInteger) {
        lhs = lhs << rhs
    }

    public static func >> (lhs: Tetra, rhs: some BinaryInteger) -> Tetra {
        .init(lhs.storage >> rhs)
    }

    public static func >>= (lhs: inout Tetra, rhs: some BinaryInteger) {
        lhs = lhs >> rhs
    }

    public static func < (lhs: Tetra, rhs: Tetra) -> Bool {
        lhs.storage < rhs.storage
    }

    public init(integerLiteral value: UInt32) {
        storage = value
    }
}

/// MMIX Wyde - 16-bit unsigned value (two bytes)
///
/// Represents a 2-byte value using 2's-complement arithmetic.
/// While storage is unsigned, MMIX instructions interpret values as signed
/// or unsigned depending on the opcode.
public struct Wyde: Sendable, Hashable, Codable {
    /// Underlying 16-bit unsigned storage.
    public var storage: UInt16

    /// Create from an unsigned value.
    /// - parameter value: The 16-bit quantity to use.
    public init(_ value: UInt16) {
        storage = value
    }

    /// Initialize with any integer type, truncating if needed.
    /// - parameter value: A binary integer.
    public init(truncatingIfNeeded value: some BinaryInteger) {
        storage = .init(truncatingIfNeeded: value)
    }

    /// Initialize truncating bits from another integer type.
    /// Required by FixedWidthInteger protocol.
    /// - parameter source: The source value to truncate.
    public init(_truncatingBits source: UInt) {
        storage = UInt16(truncatingIfNeeded: source)
    }

    /// Two's-complement signed interpretation.
    ///
    /// - Note: Many MMIX instructions need both signed and unsigned views of the same bits.
    public var asSigned: Int16 {
        Int16(bitPattern: storage)
    }

    /// Create from a two's-complement signed value.
    /// - parameter value: The signed quantity to use.
    public init(signed value: Int16) {
        storage = .init(bitPattern: value)
    }

    /// Zero constant.
    public static let zero = Wyde(0)

    /// Maximum value.
    public static let max = Wyde(UInt16.max)
}

// MARK: - Wyde Multi-byte decomposition (big-endian)

extension Wyde {
    /// Extract high byte (bits 15–8).
    public var highByte: Byte {
        Byte(UInt8(truncatingIfNeeded: storage >> 8))
    }

    /// Extract low byte (bits 7–0).
    public var lowByte: Byte {
        Byte(UInt8(truncatingIfNeeded: storage & 0xFF))
    }

    /// Construct from two bytes (big-endian: high || low).
    ///
    /// - parameters:
    ///   - high: High 8-bit byte.
    ///   - low: Low 8-bit byte.
    public init(high: Byte, low: Byte) {
        storage = UInt16(high.storage) << 8 | UInt16(low.storage)
    }

    /// Get bytes as array [high, low].
    public var bytes: [Byte] {
        [highByte, lowByte]
    }

    /// Initialize using a collection of raw bytes.
    ///
    /// - Note: This is explicitly a slow-path implementation, intended for use
    ///   when reading unaligned values. 
    public init<C: Collection>(bytes: C) where C.Element == Byte, C.Index == Int {
        self.init(high: bytes[0], low: bytes[1])
    }
}

// MARK: - Wyde Arithmetic Operations

extension Wyde {
    /// Signed comparison.
    public func signedCompare(to other: Wyde) -> ComparisonResult {
        let a = self.asSigned
        let b = other.asSigned
        if a < b { return .less }
        if a > b { return .greater }
        return .equal
    }

    /// Unsigned comparison.
    public func unsignedCompare(to other: Wyde) -> ComparisonResult {
        if storage < other.storage { return .less }
        if storage > other.storage { return .greater }
        return .equal
    }

    /// Add with overflow detection.
    public func addingReportingOverflow(_ other: Wyde) -> (partialValue: Wyde, overflow: Bool) {
        let (result, overflow) = storage.addingReportingOverflow(other.storage)
        return (.init(result), overflow)
    }

    /// Signed addition with overflow detection.
    public func signedAddingReportingOverflow(_ other: Wyde) -> (partialValue: Wyde, overflow: Bool) {
        let (result, overflow) = asSigned.addingReportingOverflow(other.asSigned)
        return (.init(signed: result), overflow)
    }

    /// Multiply returning high and low words.
    public func multipliedFullWidth(by other: Wyde) -> (high: Wyde, low: Wyde) {
        let result = storage.multipliedFullWidth(by: other.storage)
        return (Wyde(result.high), Wyde(result.low))
    }

    /// Division with remainder.
    public func quotientAndRemainder(dividingBy other: Wyde) -> (quotient: Wyde, remainder: Wyde) {
        guard other.storage != 0 else {
            return (.zero, self)
        }
        let (quotient, remainder) = storage.quotientAndRemainder(dividingBy: other.storage)
        return (Wyde(quotient), Wyde(remainder))
    }
}

// MARK: - Wyde Protocol Conformance

extension Wyde: FixedWidthInteger, UnsignedInteger {
    public static var bitWidth: Int { 16 }
    public static var isSigned: Bool { false }
    public static var min: Wyde { .zero }

    public var words: [UInt] {
        [UInt(storage)]
    }

    public var trailingZeroBitCount: Int {
        storage.trailingZeroBitCount
    }

    public static func / (lhs: Wyde, rhs: Wyde) -> Wyde {
        .init(lhs.storage / rhs.storage)
    }

    public static func /= (lhs: inout Wyde, rhs: Wyde) {
        lhs = lhs / rhs
    }

    public static func % (lhs: Wyde, rhs: Wyde) -> Wyde {
        .init(lhs.storage % rhs.storage)
    }

    public static func %= (lhs: inout Wyde, rhs: Wyde) {
        lhs = lhs % rhs
    }

    public var magnitude: Wyde { self }

    public init?<T>(exactly source: T) where T : BinaryInteger {
        guard let value = UInt16(exactly: source) else { return nil }
        self.init(value)
    }

    public static func &+ (lhs: Wyde, rhs: Wyde) -> Wyde {
        .init(lhs.storage &+ rhs.storage)
    }

    public static func &+= (lhs: inout Wyde, rhs: Wyde) {
        lhs = lhs &+ rhs
    }

    public static func &- (lhs: Wyde, rhs: Wyde) -> Wyde {
        .init(lhs.storage &- rhs.storage)
    }

    public static func &-= (lhs: inout Wyde, rhs: Wyde) {
        lhs = lhs &- rhs
    }

    public static func &* (lhs: Wyde, rhs: Wyde) -> Wyde {
        .init(lhs.storage &* rhs.storage)
    }

    public static func &*= (lhs: inout Wyde, rhs: Wyde) {
        lhs = lhs &* rhs
    }

    public static func &<< (lhs: Wyde, rhs: some BinaryInteger) -> Wyde {
        .init(lhs.storage &<< rhs)
    }

    public static func &<<= (lhs: inout Wyde, rhs: some BinaryInteger) {
        lhs = lhs &<< rhs
    }

    public static func &>> (lhs: Wyde, rhs: some BinaryInteger) -> Wyde {
        .init(lhs.storage &>> rhs)
    }

    public static func &>>= (lhs: inout Wyde, rhs: some BinaryInteger) {
        lhs = lhs &>> rhs
    }

    public init(clamping source: some BinaryInteger) {
        if source < 0 {
            self = .zero
        } else if source > UInt16.max {
            self = .max
        } else {
            self.init(UInt16(source))
        }
    }

    public func subtractingReportingOverflow(_ rhs: Wyde) -> (partialValue: Wyde, overflow: Bool) {
        let (result, overflow) = storage.subtractingReportingOverflow(rhs.storage)
        return (.init(result), overflow)
    }

    public func multipliedReportingOverflow(by rhs: Wyde) -> (partialValue: Wyde, overflow: Bool) {
        let (result, overflow) = storage.multipliedReportingOverflow(by: rhs.storage)
        return (.init(result), overflow)
    }

    public func dividedReportingOverflow(by rhs: Wyde) -> (partialValue: Wyde, overflow: Bool) {
        guard rhs.storage != 0 else {
            return (self, true)
        }
        let (result, overflow) = storage.dividedReportingOverflow(by: rhs.storage)
        return (.init(result), overflow)
    }

    public func remainderReportingOverflow(dividingBy rhs: Wyde) -> (partialValue: Wyde, overflow: Bool) {
        guard rhs.storage != 0 else {
            return (self, true)
        }
        let (result, overflow) = storage.remainderReportingOverflow(dividingBy: rhs.storage)
        return (.init(result), overflow)
    }

    public func dividingFullWidth(_ dividend: (high: Wyde, low: Wyde)) -> (quotient: Wyde, remainder: Wyde) {
        let (quotient, remainder) = storage.dividingFullWidth((dividend.high.storage, dividend.low.storage))
        return (Wyde(quotient), Wyde(remainder))
    }

    public var nonzeroBitCount: Int {
        storage.nonzeroBitCount
    }

    public var leadingZeroBitCount: Int {
        storage.leadingZeroBitCount
    }

    public var byteSwapped: Wyde {
        .init(storage.byteSwapped)
    }

    public static func + (lhs: Wyde, rhs: Wyde) -> Wyde {
        .init(lhs.storage &+ rhs.storage)
    }

    public static func += (lhs: inout Wyde, rhs: Wyde) {
        lhs = lhs + rhs
    }

    public static func - (lhs: Wyde, rhs: Wyde) -> Wyde {
        .init(lhs.storage &- rhs.storage)
    }

    public static func -= (lhs: inout Wyde, rhs: Wyde) {
        lhs = lhs - rhs
    }

    public static func * (lhs: Wyde, rhs: Wyde) -> Wyde {
        .init(lhs.storage &* rhs.storage)
    }

    public static func *= (lhs: inout Wyde, rhs: Wyde) {
        lhs = lhs * rhs
    }

    public static func & (lhs: Wyde, rhs: Wyde) -> Wyde {
        .init(lhs.storage & rhs.storage)
    }

    public static func &= (lhs: inout Wyde, rhs: Wyde) {
        lhs = lhs & rhs
    }

    public static func | (lhs: Wyde, rhs: Wyde) -> Wyde {
        .init(lhs.storage | rhs.storage)
    }

    public static func |= (lhs: inout Wyde, rhs: Wyde) {
        lhs = lhs | rhs
    }

    public static func ^ (lhs: Wyde, rhs: Wyde) -> Wyde {
        .init(lhs.storage ^ rhs.storage)
    }

    public static func ^= (lhs: inout Wyde, rhs: Wyde) {
        lhs = lhs ^ rhs
    }

    public static prefix func ~ (operand: Wyde) -> Wyde {
        .init(~operand.storage)
    }

    public static func << (lhs: Wyde, rhs: some BinaryInteger) -> Wyde {
        .init(lhs.storage << rhs)
    }

    public static func <<= (lhs: inout Wyde, rhs: some BinaryInteger) {
        lhs = lhs << rhs
    }

    public static func >> (lhs: Wyde, rhs: some BinaryInteger) -> Wyde {
        .init(lhs.storage >> rhs)
    }

    public static func >>= (lhs: inout Wyde, rhs: some BinaryInteger) {
        lhs = lhs >> rhs
    }

    public static func < (lhs: Wyde, rhs: Wyde) -> Bool {
        lhs.storage < rhs.storage
    }

    public init(integerLiteral value: UInt16) {
        storage = value
    }
}

/// MMIX Byte - 8-bit unsigned value (smallest addressable unit)
///
/// Represents a 1-byte value using 2's-complement arithmetic.
/// While storage is unsigned, MMIX instructions interpret values as signed
/// or unsigned depending on the opcode.
public struct Byte: Sendable, Hashable, Codable {
    /// Underlying 8-bit unsigned storage.
    public var storage: UInt8

    /// Create from an unsigned value.
    /// - parameter value: The 8-bit quantity to use.
    public init(_ value: UInt8) {
        storage = value
    }

    /// Initialize with any integer type, truncating if needed.
    /// - parameter value: A binary integer.
    public init(truncatingIfNeeded value: some BinaryInteger) {
        storage = .init(truncatingIfNeeded: value)
    }

    /// Initialize truncating bits from another integer type.
    /// Required by FixedWidthInteger protocol.
    /// - parameter source: The source value to truncate.
    public init(_truncatingBits source: UInt) {
        storage = UInt8(truncatingIfNeeded: source)
    }

    /// Two's-complement signed interpretation.
    ///
    /// - Note: Many MMIX instructions need both signed and unsigned views of the same bits.
    public var asSigned: Int8 {
        Int8(bitPattern: storage)
    }

    /// Create from a two's-complement signed value.
    /// - parameter value: The signed quantity to use.
    public init(signed value: Int8) {
        storage = .init(bitPattern: value)
    }

    /// Zero constant.
    public static let zero = Byte(0)

    /// Maximum value.
    public static let max = Byte(UInt8.max)
}

// MARK: - Byte Arithmetic Operations

extension Byte {
    /// Signed comparison.
    public func signedCompare(to other: Byte) -> ComparisonResult {
        let a = self.asSigned
        let b = other.asSigned
        if a < b { return .less }
        if a > b { return .greater }
        return .equal
    }

    /// Unsigned comparison.
    public func unsignedCompare(to other: Byte) -> ComparisonResult {
        if storage < other.storage { return .less }
        if storage > other.storage { return .greater }
        return .equal
    }

    /// Add with overflow detection.
    public func addingReportingOverflow(_ other: Byte) -> (partialValue: Byte, overflow: Bool) {
        let (result, overflow) = storage.addingReportingOverflow(other.storage)
        return (.init(result), overflow)
    }

    /// Signed addition with overflow detection.
    public func signedAddingReportingOverflow(_ other: Byte) -> (partialValue: Byte, overflow: Bool) {
        let (result, overflow) = asSigned.addingReportingOverflow(other.asSigned)
        return (.init(signed: result), overflow)
    }

    /// Multiply returning high and low words.
    public func multipliedFullWidth(by other: Byte) -> (high: Byte, low: Byte) {
        let result = storage.multipliedFullWidth(by: other.storage)
        return (Byte(result.high), Byte(result.low))
    }

    /// Division with remainder.
    public func quotientAndRemainder(dividingBy other: Byte) -> (quotient: Byte, remainder: Byte) {
        guard other.storage != 0 else {
            return (.zero, self)
        }
        let (quotient, remainder) = storage.quotientAndRemainder(dividingBy: other.storage)
        return (Byte(quotient), Byte(remainder))
    }
}

// MARK: - Byte Protocol Conformance

extension Byte: FixedWidthInteger, UnsignedInteger {
    public static var bitWidth: Int { 8 }
    public static var isSigned: Bool { false }
    public static var min: Byte { .zero }

    public var words: [UInt] {
        [UInt(storage)]
    }

    public var trailingZeroBitCount: Int {
        storage.trailingZeroBitCount
    }

    public static func / (lhs: Byte, rhs: Byte) -> Byte {
        .init(lhs.storage / rhs.storage)
    }

    public static func /= (lhs: inout Byte, rhs: Byte) {
        lhs = lhs / rhs
    }

    public static func % (lhs: Byte, rhs: Byte) -> Byte {
        .init(lhs.storage % rhs.storage)
    }

    public static func %= (lhs: inout Byte, rhs: Byte) {
        lhs = lhs % rhs
    }

    public var magnitude: Byte { self }

    public init?<T>(exactly source: T) where T : BinaryInteger {
        guard let value = UInt8(exactly: source) else { return nil }
        self.init(value)
    }

    public static func &+ (lhs: Byte, rhs: Byte) -> Byte {
        .init(lhs.storage &+ rhs.storage)
    }

    public static func &+= (lhs: inout Byte, rhs: Byte) {
        lhs = lhs &+ rhs
    }

    public static func &- (lhs: Byte, rhs: Byte) -> Byte {
        .init(lhs.storage &- rhs.storage)
    }

    public static func &-= (lhs: inout Byte, rhs: Byte) {
        lhs = lhs &- rhs
    }

    public static func &* (lhs: Byte, rhs: Byte) -> Byte {
        .init(lhs.storage &* rhs.storage)
    }

    public static func &*= (lhs: inout Byte, rhs: Byte) {
        lhs = lhs &* rhs
    }

    public static func &<< (lhs: Byte, rhs: some BinaryInteger) -> Byte {
        .init(lhs.storage &<< rhs)
    }

    public static func &<<= (lhs: inout Byte, rhs: some BinaryInteger) {
        lhs = lhs &<< rhs
    }

    public static func &>> (lhs: Byte, rhs: some BinaryInteger) -> Byte {
        .init(lhs.storage &>> rhs)
    }

    public static func &>>= (lhs: inout Byte, rhs: some BinaryInteger) {
        lhs = lhs &>> rhs
    }

    public init(clamping source: some BinaryInteger) {
        if source < 0 {
            self = .zero
        } else if source > UInt8.max {
            self = .max
        } else {
            self.init(UInt8(source))
        }
    }

    public func subtractingReportingOverflow(_ rhs: Byte) -> (partialValue: Byte, overflow: Bool) {
        let (result, overflow) = storage.subtractingReportingOverflow(rhs.storage)
        return (.init(result), overflow)
    }

    public func multipliedReportingOverflow(by rhs: Byte) -> (partialValue: Byte, overflow: Bool) {
        let (result, overflow) = storage.multipliedReportingOverflow(by: rhs.storage)
        return (.init(result), overflow)
    }

    public func dividedReportingOverflow(by rhs: Byte) -> (partialValue: Byte, overflow: Bool) {
        guard rhs.storage != 0 else {
            return (self, true)
        }
        let (result, overflow) = storage.dividedReportingOverflow(by: rhs.storage)
        return (.init(result), overflow)
    }

    public func remainderReportingOverflow(dividingBy rhs: Byte) -> (partialValue: Byte, overflow: Bool) {
        guard rhs.storage != 0 else {
            return (self, true)
        }
        let (result, overflow) = storage.remainderReportingOverflow(dividingBy: rhs.storage)
        return (.init(result), overflow)
    }

    public func dividingFullWidth(_ dividend: (high: Byte, low: Byte)) -> (quotient: Byte, remainder: Byte) {
        let (quotient, remainder) = storage.dividingFullWidth((dividend.high.storage, dividend.low.storage))
        return (Byte(quotient), Byte(remainder))
    }

    public var nonzeroBitCount: Int {
        storage.nonzeroBitCount
    }

    public var leadingZeroBitCount: Int {
        storage.leadingZeroBitCount
    }

    public var byteSwapped: Byte {
        .init(storage.byteSwapped)
    }

    public static func + (lhs: Byte, rhs: Byte) -> Byte {
        .init(lhs.storage &+ rhs.storage)
    }

    public static func += (lhs: inout Byte, rhs: Byte) {
        lhs = lhs + rhs
    }

    public static func - (lhs: Byte, rhs: Byte) -> Byte {
        .init(lhs.storage &- rhs.storage)
    }

    public static func -= (lhs: inout Byte, rhs: Byte) {
        lhs = lhs - rhs
    }

    public static func * (lhs: Byte, rhs: Byte) -> Byte {
        .init(lhs.storage &* rhs.storage)
    }

    public static func *= (lhs: inout Byte, rhs: Byte) {
        lhs = lhs * rhs
    }

    public static func & (lhs: Byte, rhs: Byte) -> Byte {
        .init(lhs.storage & rhs.storage)
    }

    public static func &= (lhs: inout Byte, rhs: Byte) {
        lhs = lhs & rhs
    }

    public static func | (lhs: Byte, rhs: Byte) -> Byte {
        .init(lhs.storage | rhs.storage)
    }

    public static func |= (lhs: inout Byte, rhs: Byte) {
        lhs = lhs | rhs
    }

    public static func ^ (lhs: Byte, rhs: Byte) -> Byte {
        .init(lhs.storage ^ rhs.storage)
    }

    public static func ^= (lhs: inout Byte, rhs: Byte) {
        lhs = lhs ^ rhs
    }

    public static prefix func ~ (operand: Byte) -> Byte {
        .init(~operand.storage)
    }

    public static func << (lhs: Byte, rhs: some BinaryInteger) -> Byte {
        .init(lhs.storage << rhs)
    }

    public static func <<= (lhs: inout Byte, rhs: some BinaryInteger) {
        lhs = lhs << rhs
    }

    public static func >> (lhs: Byte, rhs: some BinaryInteger) -> Byte {
        .init(lhs.storage >> rhs)
    }

    public static func >>= (lhs: inout Byte, rhs: some BinaryInteger) {
        lhs = lhs >> rhs
    }

    public static func < (lhs: Byte, rhs: Byte) -> Bool {
        lhs.storage < rhs.storage
    }

    public init(integerLiteral value: UInt8) {
        storage = value
    }
}

// MARK: - MachineKit Conformance

extension Octa: MachineWord {
    public typealias Storage = UInt64

    public init(truncating storage: Storage) {
        self.storage = storage
    }
}
