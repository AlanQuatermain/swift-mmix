//
//  Numerics.swift
//  swift-mmix
//
//  Created by Jim Dovey on 9/30/25.
//

import MachineKit

/// Field specification for MIX words.
///
/// Encoded as `F = 8*L + R` where `L,R` ∈ `[0,5]`.
///
/// - `L=0`: include sign.
/// - `L=1-5`: start at byte `L`.
/// - `R=0-5`: end at byte `R` (or sign if `R=0`).
public struct FieldSpec: Sendable, Hashable, Codable {
    /// Left boundary (0 = sign, 1-5 = bytes).
    public let left: UInt8

    /// Right boundary (0 = sign, 1-5 = bytes).
    public let right: UInt8

    /// Create field spec from boundaries.
    public init(left: UInt8, right: UInt8) {
        precondition(left <= 5 && right <= 5, "Field bounds must be 0...5")
        precondition(left <= right, "Left must be <= right")
        self.left = left
        self.right = right
    }

    /// Decode from F-field encoding (`F = 8*L + R`).
    public init(encoded: UInt8) {
        self.left = encoded / 8
        self.right = encoded % 8
        precondition(left <= 5 && right <= 5, "Invalid field spec: \(encoded)")
        precondition(left <= right, "Invalid field spec: \(encoded)")
    }

    /// Encode to F-field value.
    public var encoded: UInt8 {
        left * 8 + right
    }

    /// Does this field include the sign (`L == 0`)?
    public var includesSign: Bool {
        left == 0
    }

    /// Number of bytes in field (excluding sign if `L=0`).
    public var byteCount: Int {
        // Special case: (0:0) selects only sign, no bytes
        if left == 0 && right == 0 {
            return 0
        }
        let startByte = max(Int(left), 1)
        let endByte = max(Int(right), 1)
        return endByte - startByte + 1
    }

    // MARK: Common field specifications.

    /// Entire word field specification (0:5).
    public static let full = FieldSpec(left: 0, right: 5)

    /// Sign only field specification (0:0).
    public static let signOnly = FieldSpec(left: 0, right: 0)

    /// Field spec for bytes without sign (1:5).
    public static let bytes = FieldSpec(left: 1, right: 5)

    /// 2-byte address field specification (4:5).
    public static let address = FieldSpec(left: 4, right: 5)

    /// Left 3 bytes field specification (1:3).
    public static let leftHalf = FieldSpec(left: 1, right: 3)

    /// Right 3 bytes field specification (3:5).
    public static let rightHalf = FieldSpec(left: 3, right: 5)
}

// MARK: -

/// MIX word --- sign plus five 6-bit bytes.
///
/// Design notes:
///
/// - Sign-magnitude representation (not two's-complement).
/// - Both `+0` and `-0` exist and must remain distinct.
/// - Each byte is 6 bits in size (values 0–63).
/// - Total: 1 sign bit + 30 payload bits = 31 bits used.
/// - Storage: 32-bit with bit 31 = sign, bits 29–0 = magnitude.
///
/// Memory layout in `UInt32`:
///
/// - Bit 31: sign (0 = positive, 1 = negative).
/// - Bit 30: unused.
/// - Bits 29–0: five 6-bit bytes (30 bits total).
public struct MIXWord: Sendable, Hashable, Codable {
    private var bits: UInt32

    private init(bits: UInt32) {
        self.bits = bits
    }

    // MARK: Sign and Magnitude Access

    /// Sign bit (false = positive, true = negative).
    public var isNegative: Bool {
        get { (bits & 0x8000_0000) != 0 }
        set {
            if newValue {
                bits |= 0x8000_0000
            } else {
                bits &= 0x7FFF_FFFF
            }
        }
    }

    /// Magnitude (30-bit unsigned payload).
    public var magnitude: UInt32 {
        get { bits & 0x3FFF_FFFF }
        set {
            precondition(newValue < 0x3FFF_FFFF, "Magnitude exceeds 30 bits")
            bits = (bits & 0x8000_0000) | newValue
        }
    }

    /// Create from sign an magnitude.
    public init(sign: Bool, magnitude: UInt32) {
        precondition(magnitude <= 0x3FFF_FFFF, "Magnitude exceeds 30 bits")
        bits = (sign ? 0x8000_0000 : 0) | magnitude
    }

    // MARK: Zero Constants

    /// Positive zero (`+0`).
    public static let positiveZero = MIXWord(sign: false, magnitude: 0)

    /// Negative zero (`-0`).
    ///
    /// - Note: MIX distinguishes `+0` and `-0`.  They compare equal but have
    ///   different bit patterns and should remain distinct.
    public static let negativeZero = MIXWord(sign: true, magnitude: 0)

    /// Check if the value is zero (either `+0` or `-0`).
    public var isZero: Bool {
        magnitude == 0
    }

    // MARK: Byte Access

    /// Access individual bytes (1-indexed: 1...5).
    ///
    /// Byte 1 is the most significant, byte 5 is least significant.
    public subscript(byteIndex: Int) -> UInt8 {
        get {
            precondition(1...5 ~= byteIndex, "Byte index out of range")
            let shift = (5 - byteIndex) * 6
            return UInt8((magnitude >> shift) & 0x3F)
        }
        set {
            precondition(1...5 ~= byteIndex, "Byte index out of range")
            precondition(newValue <= 0x3F, "Byte value exceeds 6 bits")
            let shift = (5 - byteIndex) * 6
            let mask = UInt32(0x3F) << shift
            magnitude = (magnitude & ~mask) | (UInt32(newValue) << shift)
        }
    }

    /// Get all bytes as array (`[byte1, byte2, byte3, byte4, byte5]`).
    public var bytes: [UInt8] {
        (1...5).map { self[$0] }
    }

    /// Create from sign and byte array.
    public init(sign: Bool, bytes: some Collection<UInt8>) {
        precondition(bytes.count == 5, "MIX word requires exactly 5 bytes")
        precondition(bytes.allSatisfy { $0 < 64 }, "MIX bytes must be 6-bit (0...63)")

        var mag: UInt32 = 0
        for (index, byte) in bytes.enumerated() {
            let shift = (4 - index) * 6
            mag |= UInt32(byte) << shift
        }
        self.init(sign: sign, magnitude: mag)
    }

    // MARK: Address Management

    /// Extract an address field (the lowest-order two bytes + sign).
    public var addressField: MIXWord {
        MIXWord(sign: isNegative, magnitude: magnitude & 0x0FFF)
    }

    // MARK: Numeric Conversions

    /// Convert to signed Int32 (sign-magnitude to two's-complement).
    public var signedValue: Int32 {
        let mag = Int32(magnitude)
        return isNegative ? -mag : mag
    }

    /// Create from a signed 32-bit integer.
    public init(_ value: Int32) {
        if value >= 0 {
            self.init(sign: false, magnitude: UInt32(value))
        }
        else if value == Int32.min {
            // Special case: cannot represent abs(Int32.min) in Int32.
            // But that doesn't matter anyway, since we've exceeded 30 bits.
            preconditionFailure("Magnitude exceeds 30 bits")
        }
        else {
            self.init(sign: true, magnitude: UInt32(-value))
        }
    }
}

// MARK: - Arithmetic Operations

extension MIXWord {
    /// Negate by inverting the sign.
    public func negated() -> MIXWord {
        .init(bits: bits ^ 0x8000_0000)
    }

    /// Add with overflow detection.
    ///
    /// Uses sign-magnitude arithmetic, not two's-complement.
    public func adding(_ other: MIXWord) -> (result: MIXWord, overflow: Bool) {
        let a = self.signedValue
        let b = other.signedValue
        let (sum, overflow) = a.addingReportingOverflow(b)

        // Check if result exceeds 30-bit magnitude.
        let absSum = sum < 0 ? (sum == Int32.min ? Int32.max : -sum) : sum
        let resultOverflow = overflow || absSum > 0x3FFF_FFFF

        // Truncate to 30 bits if overflowed
        let truncatedSum = sum < 0 ?
            MIXWord(sign: true, magnitude: UInt32(absSum) & 0x3FFF_FFFF) :
            MIXWord(sign: false, magnitude: UInt32(absSum) & 0x3FFF_FFFF)

        return (truncatedSum, resultOverflow)
    }

    /// Subtract with overflow detection.
    public func subtracting(_ other: MIXWord) -> (result: MIXWord, overflow: Bool) {
        return adding(other.negated())
    }

    /// Multiply (returns 10-byte result in A:X form).
    ///
    /// Result magnitude may be up to 60 bits.  Sign of result is XOR of input
    /// signs.
    public func multiplied(by other: MIXWord) -> (high: MIXWord, low: MIXWord) {
        let a = UInt64(magnitude)
        let b = UInt64(other.magnitude)
        let product = a * b

        let sign = isNegative != other.isNegative


        // Split 60-bit result into two 30-bit words
        let high = UInt32((product >> 30) & 0x3FFF_FFFF)
        let low = UInt32(product & 0x3FFF_FFFF)

        return (
            MIXWord(sign: sign, magnitude: high),
            MIXWord(sign: sign, magnitude: low))
    }

    /// Divide (returns quotient and remainder).
    ///
    /// Dividend is 10-byte value (high:low). Divisor is a single word.
    ///
    /// - Important: Division by zero should be handled by caller.
    public static func divide(
        high: MIXWord, low: MIXWord, by divisor: MIXWord
    ) -> (quotient: MIXWord, remainder: MIXWord)? {
        guard !divisor.isZero else { return nil }

        let dividend = (UInt64(high.magnitude) << 30) | UInt64(low.magnitude)
        let divisorMag = UInt64(divisor.magnitude)

        let (quotient, remainder) = dividend.quotientAndRemainder(dividingBy: divisorMag)

        let qSign = high.isNegative != divisor.isNegative
        let rSign = high.isNegative

        return (
            MIXWord(sign: qSign, magnitude: UInt32(quotient)),
            MIXWord(sign: rSign, magnitude: UInt32(remainder)))
    }

    /// Compare (returns `.less`, `.equal`, or `.greater`).
    ///
    /// - Important: `+0` and `–0` compare as equal.
    public func compare(to other: MIXWord) -> ComparisonResult {
        let a = self.signedValue
        let b = other.signedValue

        if a < b { return .less }
        if a > b { return .greater }
        return .equal
    }
}

// MARK: - Shifts and Rotations

extension MIXWord {
    /// Shifts bytes left by the given number of bytes.
    ///
    /// If `count` is `0`, this is a no-op. If `count > 5`, returns zero with
    /// the same sign as the receiver. Otherwise, performs a bit-shift of
    /// `count * 6` bits of the *magnitude* of the receiver.
    ///
    /// - parameter count: The distance (in bytes) to shift.
    public func shiftBytesLeft(by count: Int) -> MIXWord {
        guard count != 0 else { return self }
        guard count <= 5 else {
            return isNegative ? .negativeZero : .positiveZero
        }

        let newMag = (magnitude << (count * 6)) & 0x3FFF_FFFF
        return MIXWord(sign: isNegative, magnitude: newMag)
    }

    /// Shifts bytes right by the given number of bytes.
    ///
    /// If `count` is `0`, this is a no-op. If `count > 5`, returns zero with
    /// the same sign as the receiver. Otherwise, performs a bit-shift of
    /// `count * 6` bits of the *magnitude* of the receiver.
    ///
    /// - parameter count: The distance (in bytes) to shift.
    public func shiftBytesRight(by count: Int) -> MIXWord {
        guard count != 0 else { return self }
        guard count <= 5 else {
            return isNegative ? .negativeZero : .positiveZero
        }

        let newMag = (magnitude >> (count * 6)) & 0x3FFF_FFFF
        return MIXWord(sign: isNegative, magnitude: newMag)
    }

    /// Shifts bytes left by the given number of bytes, for a (high:low)
    /// double-word.
    ///
    /// If `count` is `0`, this is a no-op. If `count > 10`, returns zero with
    /// the same sign as the receiver. Otherwise, performs a bit-shift of
    /// `count * 6` bits of the *magnitude* of the receiver.
    ///
    /// - parameter count: The distance (in bytes) to shift.
    public static func shiftBytesLeft(high: MIXWord, low: MIXWord, by count: Int) -> (high: MIXWord, low: MIXWord) {
        guard count != 0 else { return (high, low) }
        guard count <= 10 else {
            return (
                high.isNegative ? .negativeZero : .positiveZero,
                low.isNegative ? .negativeZero : .positiveZero)
        }

        // Load into a 64-bit type.
        let totalMag: UInt64 = ((UInt64(high.magnitude) << 30) | UInt64(low.magnitude))
        let newMag = totalMag << (count * 6)
        let newHi = UInt32((newMag & 0x0FFF_FFFF_C000_0000) >> 30)
        let newLo = UInt32(newMag & 0x3FFF_FFFF)

        return (
            MIXWord(sign: high.isNegative, magnitude: newHi),
            MIXWord(sign: low.isNegative, magnitude: newLo)
        )
    }

    /// Shifts bytes right by the given number of bytes, for a (high:low)
    /// double-word.
    ///
    /// If `count` is `0`, this is a no-op. If `count > 10`, returns zero with
    /// the same sign as the receiver. Otherwise, performs a bit-shift of
    /// `count * 6` bits of the *magnitude* of the receiver.
    ///
    /// - parameter count: The distance (in bytes) to shift.
    public func shiftBytesRight(high: MIXWord, low: MIXWord, by count: Int) -> (high: MIXWord, low: MIXWord) {
        guard count != 0 else { return (high, low) }
        guard count <= 10 else {
            return (
                high.isNegative ? .negativeZero : .positiveZero,
                low.isNegative ? .negativeZero : .positiveZero)
        }

        // Load into a 64-bit type.
        let totalMag: UInt64 = ((UInt64(high.magnitude) << 30) | UInt64(low.magnitude))
        let newMag = totalMag >> (count * 6)
        let newHi = UInt32((newMag & 0x0FFF_FFFF_C000_0000) >> 30)
        let newLo = UInt32(newMag & 0x3FFF_FFFF)

        return (
            MIXWord(sign: high.isNegative, magnitude: newHi),
            MIXWord(sign: low.isNegative, magnitude: newLo)
        )
    }

    /// Rotates bytes left by the given number of bytes.
    ///
    /// If `count` is `0`, this is a no-op. Otherwise, rotates the bytes of the
    /// receiver left by `count % 5`.
    ///
    /// - parameter count: The distance (in bytes) to rotate.
    public func rotateBytesLeft(by count: Int) -> MIXWord {
        guard count != 0 else { return self }
        let count = count % 5

        let buf = self.bytes + self.bytes
        return MIXWord(sign: isNegative, bytes: buf[count..<(count+5)])
    }

    /// Rotates bytes right by the given number of bytes.
    ///
    /// If `count` is `0`, this is a no-op. Otherwise, rotates the bytes of the
    /// receiver right by `count % 5`.
    ///
    /// - parameter count: The distance (in bytes) to rotate.
    public func rotateBytesRight(by count: Int) -> MIXWord {
        guard count != 0 else { return self }
        let count = count % 5

        let buf = self.bytes + self.bytes
        let offset = abs(count - 5)
        return MIXWord(sign: isNegative, bytes: buf[offset..<(offset+5)])
    }

    /// Rotates bytes left by the given number of bytes, for a (high:low)
    /// double-word.
    ///
    /// If `count` is `0`, this is a no-op. Otherwise, rotates the bytes of the
    /// receiver left by `count % 10`.
    ///
    /// - parameter count: The distance (in bytes) to rotate.
    public static func rotateBytesLeft(high: MIXWord, low: MIXWord, by count: Int) -> (high: MIXWord, low: MIXWord) {
        guard count != 0 else { return (high, low) }
        let count = count % 10

        let buf = high.bytes + low.bytes + high.bytes + low.bytes
        return (
            high: MIXWord(sign: high.isNegative, bytes: buf[count..<count+5]),
            low: MIXWord(sign: low.isNegative, bytes: buf[count+5..<count+10])
        )
    }

    /// Rotates bytes right by the given number of bytes, for a (high:low)
    /// double-word.
    ///
    /// If `count` is `0`, this is a no-op. Otherwise, rotates the bytes of the
    /// receiver right by `count % 10`.
    ///
    /// - parameter count: The distance (in bytes) to rotate.
    public func rotateBytesRight(high: MIXWord, low: MIXWord, by count: Int) -> (high: MIXWord, low: MIXWord) {
        guard count != 0 else { return (high, low) }
        let count = count % 10

        let buf = high.bytes + low.bytes + high.bytes + low.bytes
        let offset = abs(count - 10)
        return (
            high: MIXWord(sign: high.isNegative, bytes: buf[offset..<offset+5]),
            low: MIXWord(sign: low.isNegative, bytes: buf[offset+5..<offset+10])
        )
    }
}

// MARK: - Equatable

extension MIXWord: Equatable {
    /// Equality checks the bit pattern.
    ///
    /// - Important: `+0` and `–0` have different bit patterns, and are not
    ///   considered 'equal' by this function.  Use `isZero` or `compare(to:)`
    ///   if you want to determine numeric equality.
    public static func == (lhs: MIXWord, rhs: MIXWord) -> Bool {
        lhs.bits == rhs.bits
    }
}

// MARK: - MachineKit Protocol

extension MIXWord: MachineWord {
    public typealias Storage = UInt32
    public static var bitWidth: Int { 30 }
    public var storage: Storage { bits }

    public init(truncating storage: UInt32) {
        self.init(sign: false, magnitude: storage & 0x3FFF_FFFF)
    }
}

// MARK: - Derived Types

/// MIX Address (2 6-bit bytes, always positive)
public struct MIXAddress: Sendable, Hashable, Codable {
    public var value: UInt16    // 0...4095 (12-bit)

    public init(_ value: UInt16) {
        self.value = value & 0x0FFF
    }

    public init(fromWord word: MIXWord) {
        let bytes = word.bytes[3...].map(UInt16.init)
        self.value = (bytes[0] << 6) | bytes[1]
    }

    public var asWord: MIXWord {
        MIXWord(sign: false, magnitude: UInt32(value))
    }
}

/// MIX Byte (6-bit value)
public struct MIXByte: Sendable, Hashable, Codable {
    public var value: UInt8     // 0...63

    public init(_ value: UInt8) {
        precondition(value < 64, "MIX byte must be 0...63")
        self.value = value
    }
}
