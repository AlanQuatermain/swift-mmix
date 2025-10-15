//
//  NumericTests.swift
//  swift-mmix
//
//  MMIX Numeric Type Tests
//

import Testing
import MachineKit
@testable import MMIXArchitecture

// MARK: - Byte Tests

@Suite("MMIX Byte Tests")
struct ByteTests {
    @Test("Zero constant")
    func zeroConstant() {
        #expect(Byte.zero.storage == 0)
    }

    @Test("Signed interpretation")
    func signedInterpretation() {
        let positive = Byte(100)
        #expect(positive.asSigned == 100)

        let negative = Byte(signed: -50)
        #expect(negative.asSigned == -50)

        // Max positive and min negative
        let maxPos = Byte(signed: Int8.max)
        #expect(maxPos.asSigned == Int8.max)

        let minNeg = Byte(signed: Int8.min)
        #expect(minNeg.asSigned == Int8.min)
    }

    @Test("Signed vs unsigned comparison")
    func signedVsUnsignedComparison() {
        let a = Byte(UInt8.max - 10)  // 245, negative when signed
        let b = Byte(100)

        // Unsigned: a > b
        #expect(a.unsignedCompare(to: b) == .greater)

        // Signed: a < b (a is negative in two's complement)
        #expect(a.signedCompare(to: b) == .less)
    }

    @Test("Overflow detection")
    func overflowDetection() {
        let max = Byte(UInt8.max)
        let one = Byte(1)

        let (result, overflow) = max.addingReportingOverflow(one)
        #expect(overflow == true)
        #expect(result == .zero)  // Wraps to 0
    }

    @Test("Arithmetic wrapping")
    func arithmeticWrapping() {
        let a = Byte(200)
        let b = Byte(100)

        let sum = a + b
        #expect(sum.storage == 44)  // 300 % 256 = 44
    }
}

// MARK: - Wyde Tests

@Suite("MMIX Wyde Tests")
struct WydeTests {
    @Test("Zero constant")
    func zeroConstant() {
        #expect(Wyde.zero.storage == 0)
    }

    @Test("Byte decomposition")
    func byteDecomposition() {
        let value = Wyde(0x1234)
        #expect(value.highByte == Byte(0x12))
        #expect(value.lowByte == Byte(0x34))
    }

    @Test("Byte construction")
    func byteConstruction() {
        let high = Byte(0xAB)
        let low = Byte(0xCD)
        let wyde = Wyde(high: high, low: low)
        #expect(wyde.storage == 0xABCD)
    }

    @Test("Bytes array")
    func bytesArray() {
        let wyde = Wyde(0x5678)
        let bytes = wyde.bytes
        #expect(bytes.count == 2)
        #expect(bytes[0] == Byte(0x56))
        #expect(bytes[1] == Byte(0x78))
    }

    @Test("Collection initializer")
    func collectionInitializer() {
        let bytes: [Byte] = [Byte(0x12), Byte(0x34)]
        let wyde = Wyde(bytes: bytes)
        #expect(wyde.storage == 0x1234)
    }

    @Test("Signed operations")
    func signedOperations() {
        let a = Wyde(signed: -100)
        let b = Wyde(signed: 50)

        let (result, overflow) = a.signedAddingReportingOverflow(b)
        #expect(!overflow)
        #expect(result.asSigned == -50)
    }
}

// MARK: - Tetra Tests

@Suite("MMIX Tetra Tests")
struct TetraTests {
    @Test("Zero constant")
    func zeroConstant() {
        #expect(Tetra.zero.storage == 0)
    }

    @Test("Wyde decomposition")
    func wydeDecomposition() {
        let value = Tetra(0x1234_5678)
        #expect(value.highWyde == Wyde(0x1234))
        #expect(value.lowWyde == Wyde(0x5678))
    }

    @Test("Wyde construction")
    func wydeConstruction() {
        let high = Wyde(0xABCD)
        let low = Wyde(0xEF01)
        let tetra = Tetra(high: high, low: low)
        #expect(tetra.storage == 0xABCD_EF01)
    }

    @Test("Bytes array")
    func bytesArray() {
        let tetra = Tetra(0x12345678)
        let bytes = tetra.bytes
        #expect(bytes.count == 4)
        #expect(bytes[0] == Byte(0x12))
        #expect(bytes[1] == Byte(0x34))
        #expect(bytes[2] == Byte(0x56))
        #expect(bytes[3] == Byte(0x78))
    }

    @Test("Collection initializer")
    func collectionInitializer() {
        let bytes: [Byte] = [Byte(0x12), Byte(0x34), Byte(0x56), Byte(0x78)]
        let tetra = Tetra(bytes: bytes)
        #expect(tetra.storage == 0x12345678)
    }

    @Test("Full-width multiply")
    func fullWidthMultiply() {
        let a = Tetra(UInt32.max)
        let b = Tetra(2)

        let (high, low) = a.multipliedFullWidth(by: b)
        #expect(high == Tetra(1))
        #expect(low == Tetra(UInt32.max - 1))
    }

    @Test("Division with remainder")
    func divisionWithRemainder() {
        let dividend = Tetra(100)
        let divisor = Tetra(7)

        let (quotient, remainder) = dividend.quotientAndRemainder(dividingBy: divisor)
        #expect(quotient == Tetra(14))
        #expect(remainder == Tetra(2))
    }
}

// MARK: - Octa Tests

@Suite("MMIX Octa Tests")
struct OctaTests {
    @Test("Zero constant")
    func zeroConstant() {
        #expect(Octa.zero.storage == 0)
    }

    @Test("Signed interpretation")
    func signedInterpretation() {
        let positive = Octa(100)
        #expect(positive.asSigned == 100)

        let negative = Octa(signed: -50)
        #expect(negative.asSigned == -50)

        // Max positive and min negative
        let maxPos = Octa(signed: Int64.max)
        #expect(maxPos.asSigned == Int64.max)

        let minNeg = Octa(signed: Int64.min)
        #expect(minNeg.asSigned == Int64.min)
    }

    @Test("Tetra decomposition")
    func tetraDecomposition() {
        let value = Octa(0x1234_5678_9ABC_DEF0)
        #expect(value.highTetra == Tetra(0x1234_5678))
        #expect(value.lowTetra == Tetra(0x9ABC_DEF0))
    }

    @Test("Tetra construction")
    func tetraConstruction() {
        let high = Tetra(0xDEAD_BEEF)
        let low = Tetra(0xCAFE_BABE)
        let octa = Octa(high: high, low: low)
        #expect(octa.storage == 0xDEAD_BEEF_CAFE_BABE)
    }

    @Test("Byte extraction (big-endian)")
    func byteExtraction() {
        let value = Octa(0x0102_0304_0506_0708)
        #expect(value[0] == Byte(0x01))  // MSB
        #expect(value[1] == Byte(0x02))
        #expect(value[6] == Byte(0x07))
        #expect(value[7] == Byte(0x08))  // LSB
    }

    @Test("Byte array construction")
    func byteArrayConstruction() {
        let bytes: [Byte] = [
            Byte(0x01), Byte(0x02), Byte(0x03), Byte(0x04),
            Byte(0x05), Byte(0x06), Byte(0x07), Byte(0x08)
        ]
        let octa = Octa(bytes: bytes)
        #expect(octa.storage == 0x0102_0304_0506_0708)
    }

    @Test("Collection initializer")
    func collectionInitializer() {
        let bytes: [Byte] = [
            Byte(0x11), Byte(0x22), Byte(0x33), Byte(0x44),
            Byte(0x55), Byte(0x66), Byte(0x77), Byte(0x88)
        ]
        let octa = Octa(bytes: bytes)
        #expect(octa.storage == 0x1122_3344_5566_7788)
    }

    @Test("Signed vs unsigned comparison")
    func signedVsUnsignedComparison() {
        let a = Octa(UInt64.max - 10)  // Large unsigned
        let b = Octa(100)

        // Unsigned: a > b
        #expect(a.unsignedCompare(to: b) == .greater)

        // Signed: a < b (a is negative in two's complement)
        #expect(a.signedCompare(to: b) == .less)
    }

    @Test("Overflow detection")
    func overflowDetection() {
        let max = Octa(UInt64.max)
        let one = Octa(1)

        let (result, overflow) = max.addingReportingOverflow(one)
        #expect(overflow == true)
        #expect(result == .zero)  // Wraps to 0
    }

    @Test("Signed overflow detection")
    func signedOverflowDetection() {
        let maxPos = Octa(signed: Int64.max)
        let one = Octa(1)

        let (result, overflow) = maxPos.signedAddingReportingOverflow(one)
        #expect(overflow == true)
        #expect(result.asSigned == Int64.min)  // Wraps to min
    }

    @Test("Full-width multiply")
    func fullWidthMultiply() {
        let a = Octa(UInt64.max)
        let b = Octa(2)

        let (high, low) = a.multipliedFullWidth(by: b)
        #expect(high == Octa(1))
        #expect(low == Octa(UInt64.max - 1))
    }

    @Test("Division with remainder")
    func divisionWithRemainder() {
        let dividend = Octa(1000)
        let divisor = Octa(37)

        let (quotient, remainder) = dividend.quotientAndRemainder(dividingBy: divisor)
        #expect(quotient == Octa(27))
        #expect(remainder == Octa(1))
    }

    @Test("Division by zero")
    func divisionByZero() {
        let dividend = Octa(100)
        let divisor = Octa(0)

        let (quotient, remainder) = dividend.quotientAndRemainder(dividingBy: divisor)
        #expect(quotient == .zero)
        #expect(remainder == dividend)  // Returns dividend unchanged
    }
}

// MARK: - Protocol Conformance Tests

@Suite("MMIX Protocol Conformance Tests")
struct ProtocolConformanceTests {
    @Test("Byte FixedWidthInteger conformance")
    func byteFixedWidthInteger() {
        #expect(Byte.bitWidth == 8)
        #expect(Byte.isSigned == false)
        #expect(Byte.min == Byte.zero)
        #expect(Byte.max.storage == UInt8.max)
    }

    @Test("Wyde FixedWidthInteger conformance")
    func wydeFixedWidthInteger() {
        #expect(Wyde.bitWidth == 16)
        #expect(Wyde.isSigned == false)
        #expect(Wyde.min == Wyde.zero)
        #expect(Wyde.max.storage == UInt16.max)
    }

    @Test("Tetra FixedWidthInteger conformance")
    func tetraFixedWidthInteger() {
        #expect(Tetra.bitWidth == 32)
        #expect(Tetra.isSigned == false)
        #expect(Tetra.min == Tetra.zero)
        #expect(Tetra.max.storage == UInt32.max)
    }

    @Test("Octa FixedWidthInteger conformance")
    func octaFixedWidthInteger() {
        #expect(Octa.bitWidth == 64)
        #expect(Octa.isSigned == false)
        #expect(Octa.min == Octa.zero)
        #expect(Octa.max.storage == UInt64.max)
    }

    @Test("Octa MachineWord conformance")
    func octaMachineWord() {
        let octa = Octa(0xDEADBEEF)
        #expect(octa.storage == 0xDEADBEEF)

        let truncated = Octa(truncating: 0xDEADBEEF)
        #expect(truncated.storage == 0xDEADBEEF)
    }
}

// MARK: - Bitwise Operation Tests

@Suite("MMIX Bitwise Operation Tests")
struct BitwiseOperationTests {
    @Test("Bitwise AND")
    func bitwiseAnd() {
        let a = Octa(0xFF00_FF00_FF00_FF00)
        let b = Octa(0xF0F0_F0F0_F0F0_F0F0)
        let result = a & b
        #expect(result.storage == 0xF000_F000_F000_F000)
    }

    @Test("Bitwise OR")
    func bitwiseOr() {
        let a = Octa(0xFF00_0000_0000_0000)
        let b = Octa(0x00FF_0000_0000_0000)
        let result = a | b
        #expect(result.storage == 0xFFFF_0000_0000_0000)
    }

    @Test("Bitwise XOR")
    func bitwiseXor() {
        let a = Octa(0xFFFF_FFFF_FFFF_FFFF)
        let b = Octa(0xAAAA_AAAA_AAAA_AAAA)
        let result = a ^ b
        #expect(result.storage == 0x5555_5555_5555_5555)
    }

    @Test("Bitwise NOT")
    func bitwiseNot() {
        let value = Octa(0x0F0F_0F0F_0F0F_0F0F)
        let result = ~value
        #expect(result.storage == 0xF0F0_F0F0_F0F0_F0F0)
    }

    @Test("Left shift")
    func leftShift() {
        let value = Octa(0x0000_0000_0000_00FF)
        let result = value << 8
        #expect(result.storage == 0x0000_0000_0000_FF00)
    }

    @Test("Right shift")
    func rightShift() {
        let value = Octa(0xFF00_0000_0000_0000)
        let result = value >> 8
        #expect(result.storage == 0x00FF_0000_0000_0000)
    }
}

// MARK: - Comparison Result Tests

@Suite("Comparison Result Tests")
struct ComparisonResultTests {
    @Test("Comparison result values")
    func comparisonResultValues() {
        #expect(ComparisonResult.less.rawValue == -1)
        #expect(ComparisonResult.equal.rawValue == 0)
        #expect(ComparisonResult.greater.rawValue == 1)
    }

    @Test("Comparison result equality")
    func comparisonResultEquality() {
        #expect(ComparisonResult.less == .less)
        #expect(ComparisonResult.equal == .equal)
        #expect(ComparisonResult.greater == .greater)

        #expect(ComparisonResult.less != .equal)
        #expect(ComparisonResult.equal != .greater)
    }
}
