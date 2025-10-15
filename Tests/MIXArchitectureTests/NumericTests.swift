//
//  NumericTests.swift
//  swift-mmix
//
//  MIX Numeric Type Tests
//

import Testing
import MachineKit
@testable import MIXArchitecture

// MARK: - FieldSpec Tests

@Suite("MIX FieldSpec Tests")
struct FieldSpecTests {
    @Test("Field spec encoding")
    func fieldSpecEncoding() {
        let spec = FieldSpec(left: 2, right: 4)
        #expect(spec.encoded == 2 * 8 + 4)
        #expect(spec.encoded == 20)
    }

    @Test("Field spec decoding")
    func fieldSpecDecoding() {
        let spec = FieldSpec(encoded: 20)
        #expect(spec.left == 2)
        #expect(spec.right == 4)
    }

    @Test("Field spec sign inclusion")
    func fieldSpecSignInclusion() {
        let withSign = FieldSpec(left: 0, right: 3)
        #expect(withSign.includesSign == true)

        let noSign = FieldSpec(left: 1, right: 3)
        #expect(noSign.includesSign == false)
    }

    @Test("Field spec byte count")
    func fieldSpecByteCount() {
        // (0:5) = sign + 5 bytes = 5 bytes
        #expect(FieldSpec.full.byteCount == 5)

        // (0:0) = sign only = 0 bytes
        #expect(FieldSpec.signOnly.byteCount == 0)

        // (1:5) = 5 bytes
        #expect(FieldSpec.bytes.byteCount == 5)

        // (4:5) = 2 bytes
        #expect(FieldSpec.address.byteCount == 2)

        // (2:4) = 3 bytes
        let custom = FieldSpec(left: 2, right: 4)
        #expect(custom.byteCount == 3)
    }

    @Test("Common field specs")
    func commonFieldSpecs() {
        #expect(FieldSpec.full.left == 0 && FieldSpec.full.right == 5)
        #expect(FieldSpec.signOnly.left == 0 && FieldSpec.signOnly.right == 0)
        #expect(FieldSpec.bytes.left == 1 && FieldSpec.bytes.right == 5)
        #expect(FieldSpec.address.left == 4 && FieldSpec.address.right == 5)
        #expect(FieldSpec.leftHalf.left == 1 && FieldSpec.leftHalf.right == 3)
        #expect(FieldSpec.rightHalf.left == 3 && FieldSpec.rightHalf.right == 5)
    }

    @Test("Invalid field spec bounds")
    func invalidFieldSpecBounds() async {
        await #expect(processExitsWith: .failure) {
            _ = FieldSpec(left: 6, right: 5)
        }
    }

    @Test("Invalid field spec order")
    func invalidFieldSpecOrder() async {
        await #expect(processExitsWith: .failure) {
            _ = FieldSpec(left: 3, right: 2)
        }
    }
}

// MARK: - MIXWord Tests

@Suite("MIX Word Tests")
struct MIXWordTests {
    @Test("Positive and negative zero are distinct")
    func distinctZeros() {
        let pos = MIXWord.positiveZero
        let neg = MIXWord.negativeZero

        #expect(pos.isZero && neg.isZero)
        #expect(pos != neg)  // Different bit patterns
        #expect(pos.compare(to: neg) == .equal)  // But compare equal
    }

    @Test("Sign bit access")
    func signBitAccess() {
        var word = MIXWord(sign: false, magnitude: 100)
        #expect(!word.isNegative)

        word.isNegative = true
        #expect(word.isNegative)
        #expect(word.magnitude == 100)  // Magnitude unchanged
    }

    @Test("Magnitude access")
    func magnitudeAccess() {
        var word = MIXWord(sign: true, magnitude: 500)
        #expect(word.magnitude == 500)

        word.magnitude = 1000
        #expect(word.magnitude == 1000)
        #expect(word.isNegative)  // Sign unchanged
    }

    @Test("Byte subscript access")
    func byteSubscriptAccess() {
        var word = MIXWord(sign: false, bytes: [1, 2, 3, 4, 5])
        #expect(word[1] == 1)
        #expect(word[2] == 2)
        #expect(word[3] == 3)
        #expect(word[4] == 4)
        #expect(word[5] == 5)

        word[3] = 63  // Max 6-bit value
        #expect(word[3] == 63)
        #expect(word[1] == 1)  // Others unchanged
    }

    @Test("Bytes array")
    func bytesArray() {
        let word = MIXWord(sign: true, bytes: [10, 20, 30, 40, 50])
        let bytes = word.bytes
        #expect(bytes.count == 5)
        #expect(bytes == [10, 20, 30, 40, 50])
    }

    @Test("Byte array construction")
    func byteArrayConstruction() {
        let bytes: [UInt8] = [5, 10, 15, 20, 25]
        let word = MIXWord(sign: true, bytes: bytes)
        #expect(word.isNegative)
        #expect(word[1] == 5)
        #expect(word[5] == 25)
    }

    @Test("Collection byte construction")
    func collectionByteConstruction() {
        let bytes = [UInt8](arrayLiteral: 1, 2, 3, 4, 5)
        let word = MIXWord(sign: false, bytes: bytes)
        #expect(word.bytes == [1, 2, 3, 4, 5])
    }

    @Test("Address field extraction")
    func addressFieldExtraction() {
        let word = MIXWord(sign: true, bytes: [10, 20, 30, 40, 50])
        let addr = word.addressField

        #expect(addr.isNegative)  // Sign preserved
        // Address is lowest 12 bits (bytes 4:5)
        // byte4 = 40, byte5 = 50
        // 12-bit value = (40 << 6) | 50 = 2560 + 50 = 2610
        #expect(addr.magnitude == 2610)
    }

    @Test("Signed value conversion")
    func signedValueConversion() {
        let pos = MIXWord(sign: false, magnitude: 100)
        #expect(pos.signedValue == 100)

        let neg = MIXWord(sign: true, magnitude: 100)
        #expect(neg.signedValue == -100)

        let zero = MIXWord.positiveZero
        #expect(zero.signedValue == 0)
    }

    @Test("Int32 construction positive")
    func int32ConstructionPositive() {
        let word = MIXWord(42)
        #expect(!word.isNegative)
        #expect(word.magnitude == 42)
        #expect(word.signedValue == 42)
    }

    @Test("Int32 construction negative")
    func int32ConstructionNegative() {
        let word = MIXWord(-123)
        #expect(word.isNegative)
        #expect(word.magnitude == 123)
        #expect(word.signedValue == -123)
    }

    @Test("Magnitude overflow check")
    func magnitudeOverflowCheck() async {
        await #expect(processExitsWith: .failure) {
            _ = MIXWord(sign: false, magnitude: 0x4000_0000)  // Exceeds 30 bits
        }
    }
}

// MARK: - MIXWord Arithmetic Tests

@Suite("MIX Word Arithmetic Tests")
struct MIXWordArithmeticTests {
    @Test("Negation preserves zero distinction")
    func negationPreservesZeros() {
        let pos = MIXWord.positiveZero.negated()
        #expect(pos == .negativeZero)

        let neg = MIXWord.negativeZero.negated()
        #expect(neg == .positiveZero)
    }

    @Test("Addition without overflow")
    func additionWithoutOverflow() {
        let a = MIXWord(100)
        let b = MIXWord(50)

        let (sum, overflow) = a.adding(b)
        #expect(sum.signedValue == 150)
        #expect(!overflow)
    }

    @Test("Addition with sign change")
    func additionWithSignChange() {
        let a = MIXWord(100)
        let b = MIXWord(-150)

        let (sum, overflow) = a.adding(b)
        #expect(sum.signedValue == -50)
        #expect(!overflow)
    }

    @Test("Addition with overflow")
    func additionWithOverflow() {
        let max = MIXWord(sign: false, magnitude: 0x3FFF_FFFF)  // Max 30-bit
        let one = MIXWord(1)

        let (_, overflow) = max.adding(one)
        #expect(overflow)
    }

    @Test("Subtraction without overflow")
    func subtractionWithoutOverflow() {
        let a = MIXWord(100)
        let b = MIXWord(30)

        let (diff, overflow) = a.subtracting(b)
        #expect(diff.signedValue == 70)
        #expect(!overflow)
    }

    @Test("Subtraction resulting in negative")
    func subtractionResultingInNegative() {
        let a = MIXWord(50)
        let b = MIXWord(100)

        let (diff, overflow) = a.subtracting(b)
        #expect(diff.signedValue == -50)
        #expect(!overflow)
    }

    @Test("Multiplication basic")
    func multiplicationBasic() {
        let a = MIXWord(12)
        let b = MIXWord(13)

        let (high, low) = a.multiplied(by: b)

        // 12 * 13 = 156, fits in low word
        #expect(high.magnitude == 0)
        #expect(low.magnitude == 156)
        #expect(!high.isNegative)
        #expect(!low.isNegative)
    }

    @Test("Multiplication with large values")
    func multiplicationWithLargeValues() {
        let a = MIXWord(sign: false, magnitude: 0x3FFF_FFFF)  // Max 30-bit
        let b = MIXWord(2)

        let (high, low) = a.multiplied(by: b)

        // Result is 60 bits: 0x7FFF_FFFE
        #expect(high.magnitude == 1)  // Top 30 bits
        #expect(low.magnitude == 0x3FFF_FFFE)  // Bottom 30 bits
    }

    @Test("Multiplication sign XOR")
    func multiplicationSignXOR() {
        let a = MIXWord(-10)
        let b = MIXWord(5)

        let (high, low) = a.multiplied(by: b)

        #expect(high.isNegative)  // Negative result
        #expect(low.isNegative)
        #expect(low.magnitude == 50)
    }

    @Test("Division basic")
    func divisionBasic() {
        let high = MIXWord.positiveZero
        let low = MIXWord(100)
        let divisor = MIXWord(7)

        let result = MIXWord.divide(high: high, low: low, by: divisor)
        #expect(result != nil)

        let (quotient, remainder) = result!
        #expect(quotient.magnitude == 14)
        #expect(remainder.magnitude == 2)
    }

    @Test("Division by zero")
    func divisionByZero() {
        let high = MIXWord.positiveZero
        let low = MIXWord(100)
        let divisor = MIXWord.positiveZero

        let result = MIXWord.divide(high: high, low: low, by: divisor)
        #expect(result == nil)
    }

    @Test("Division with 60-bit dividend")
    func divisionWith60BitDividend() {
        // Dividend = (high << 30) | low
        let high = MIXWord(sign: false, magnitude: 5)
        let low = MIXWord(sign: false, magnitude: 100)
        let divisor = MIXWord(1000)

        let result = MIXWord.divide(high: high, low: low, by: divisor)
        #expect(result != nil)

        let (quotient, remainder) = result!

        // (5 << 30) + 100 = 5368709220
        // 5368709220 / 1000 = 5368709, remainder 220
        #expect(quotient.magnitude == 5368709)
        #expect(remainder.magnitude == 220)
    }

    @Test("Division sign rules")
    func divisionSignRules() {
        let high = MIXWord(sign: true, magnitude: 0)
        let low = MIXWord(sign: true, magnitude: 100)
        let divisor = MIXWord(sign: false, magnitude: 7)

        let result = MIXWord.divide(high: high, low: low, by: divisor)
        let (quotient, remainder) = result!

        // Quotient sign: high.sign XOR divisor.sign = true XOR false = true
        #expect(quotient.isNegative)

        // Remainder sign: high.sign = true
        #expect(remainder.isNegative)
    }

    @Test("Comparison equal")
    func comparisonEqual() {
        let a = MIXWord(100)
        let b = MIXWord(100)

        #expect(a.compare(to: b) == .equal)
    }

    @Test("Comparison less than")
    func comparisonLessThan() {
        let a = MIXWord(50)
        let b = MIXWord(100)

        #expect(a.compare(to: b) == .less)
    }

    @Test("Comparison greater than")
    func comparisonGreaterThan() {
        let a = MIXWord(200)
        let b = MIXWord(100)

        #expect(a.compare(to: b) == .greater)
    }

    @Test("Comparison with negatives")
    func comparisonWithNegatives() {
        let a = MIXWord(-50)
        let b = MIXWord(50)

        #expect(a.compare(to: b) == .less)
    }

    @Test("Comparison +0 and -0")
    func comparisonZeros() {
        let pos = MIXWord.positiveZero
        let neg = MIXWord.negativeZero

        #expect(pos.compare(to: neg) == .equal)
    }
}

// MARK: - MIXWord Shifts and Rotations Tests

@Suite("MIX Word Shift and Rotation Tests")
struct MIXWordShiftRotationTests {
    @Test("Shift bytes left basic")
    func shiftBytesLeftBasic() {
        let word = MIXWord(sign: false, bytes: [1, 2, 3, 4, 5])
        let shifted = word.shiftBytesLeft(by: 1)

        // Bytes shift left, rightmost filled with 0
        #expect(shifted[1] == 2)
        #expect(shifted[2] == 3)
        #expect(shifted[3] == 4)
        #expect(shifted[4] == 5)
        #expect(shifted[5] == 0)
    }

    @Test("Shift bytes left preserves sign")
    func shiftBytesLeftPreservesSign() {
        let word = MIXWord(sign: true, bytes: [1, 2, 3, 4, 5])
        let shifted = word.shiftBytesLeft(by: 2)

        #expect(shifted.isNegative)
    }

    @Test("Shift bytes left overflow to zero")
    func shiftBytesLeftOverflow() {
        let word = MIXWord(sign: false, bytes: [1, 2, 3, 4, 5])
        let shifted = word.shiftBytesLeft(by: 6)

        #expect(shifted.magnitude == 0)
        #expect(!shifted.isNegative)
    }

    @Test("Shift bytes right basic")
    func shiftBytesRightBasic() {
        let word = MIXWord(sign: false, bytes: [1, 2, 3, 4, 5])
        let shifted = word.shiftBytesRight(by: 1)

        // Bytes shift right, leftmost filled with 0
        #expect(shifted[1] == 0)
        #expect(shifted[2] == 1)
        #expect(shifted[3] == 2)
        #expect(shifted[4] == 3)
        #expect(shifted[5] == 4)
    }

    @Test("Rotate bytes left")
    func rotateBytesLeft() {
        let word = MIXWord(sign: false, bytes: [1, 2, 3, 4, 5])
        let rotated = word.rotateBytesLeft(by: 2)

        #expect(rotated[1] == 3)
        #expect(rotated[2] == 4)
        #expect(rotated[3] == 5)
        #expect(rotated[4] == 1)
        #expect(rotated[5] == 2)
    }

    @Test("Rotate bytes right")
    func rotateBytesRight() {
        let word = MIXWord(sign: false, bytes: [1, 2, 3, 4, 5])
        let rotated = word.rotateBytesRight(by: 2)

        #expect(rotated[1] == 4)
        #expect(rotated[2] == 5)
        #expect(rotated[3] == 1)
        #expect(rotated[4] == 2)
        #expect(rotated[5] == 3)
    }

    @Test("Rotate wraps modulo 5")
    func rotateWrapsModulo5() {
        let word = MIXWord(sign: false, bytes: [1, 2, 3, 4, 5])
        let rotated1 = word.rotateBytesLeft(by: 7)  // 7 % 5 = 2
        let rotated2 = word.rotateBytesLeft(by: 2)

        #expect(rotated1.bytes == rotated2.bytes)
    }

    @Test("Double-word shift left")
    func doubleWordShiftLeft() {
        let high = MIXWord(sign: false, bytes: [1, 2, 3, 4, 5])
        let low = MIXWord(sign: false, bytes: [6, 7, 8, 9, 10])

        let (newHigh, newLow) = MIXWord.shiftBytesLeft(high: high, low: low, by: 1)

        // High shifts left, gets MSB from low
        #expect(newHigh[1] == 2)
        #expect(newHigh[5] == 6)

        // Low shifts left, gets 0
        #expect(newLow[1] == 7)
        #expect(newLow[5] == 0)
    }

    @Test("Double-word rotate left")
    func doubleWordRotateLeft() {
        let high = MIXWord(sign: false, bytes: [1, 2, 3, 4, 5])
        let low = MIXWord(sign: false, bytes: [6, 7, 8, 9, 10])

        let (newHigh, newLow) = MIXWord.rotateBytesLeft(high: high, low: low, by: 3)

        #expect(newHigh[1] == 4)
        #expect(newHigh[2] == 5)
        #expect(newHigh[3] == 6)
        #expect(newHigh[4] == 7)
        #expect(newHigh[5] == 8)

        #expect(newLow[1] == 9)
        #expect(newLow[2] == 10)
        #expect(newLow[3] == 1)
        #expect(newLow[4] == 2)
        #expect(newLow[5] == 3)
    }
}

// MARK: - MIXWord Equality Tests

@Suite("MIX Word Equality Tests")
struct MIXWordEqualityTests {
    @Test("Bit pattern equality")
    func bitPatternEquality() {
        let a = MIXWord(sign: false, magnitude: 100)
        let b = MIXWord(sign: false, magnitude: 100)

        #expect(a == b)
    }

    @Test("Zero distinction in equality")
    func zeroDistinctionInEquality() {
        let pos = MIXWord.positiveZero
        let neg = MIXWord.negativeZero

        #expect(pos != neg)  // Different bit patterns
    }

    @Test("Different magnitudes not equal")
    func differentMagnitudesNotEqual() {
        let a = MIXWord(sign: false, magnitude: 100)
        let b = MIXWord(sign: false, magnitude: 200)

        #expect(a != b)
    }

    @Test("Different signs not equal")
    func differentSignsNotEqual() {
        let a = MIXWord(sign: false, magnitude: 100)
        let b = MIXWord(sign: true, magnitude: 100)

        #expect(a != b)
    }
}

// MARK: - MIX Derived Types Tests

@Suite("MIX Derived Types Tests")
struct MIXDerivedTypesTests {
    @Test("MIXAddress creation")
    func mixAddressCreation() {
        let addr = MIXAddress(1234)
        #expect(addr.value == 1234)
    }

    @Test("MIXAddress truncation")
    func mixAddressTruncation() {
        let addr = MIXAddress(0x1FFF)  // Exceeds 12 bits
        #expect(addr.value == 0x0FFF)  // Truncated to 12 bits
    }

    @Test("MIXAddress from word")
    func mixAddressFromWord() {
        let word = MIXWord(sign: false, bytes: [1, 2, 3, 40, 50])
        let addr = MIXAddress(fromWord: word)

        // Address from bytes 4:5 = (40 << 6) | 50 = 2610
        #expect(addr.value == 2610)
    }

    @Test("MIXAddress to word")
    func mixAddressToWord() {
        let addr = MIXAddress(2610)
        let word = addr.asWord

        #expect(!word.isNegative)
        #expect(word.magnitude == 2610)
    }

    @Test("MIXByte creation")
    func mixByteCreation() {
        let byte = MIXByte(42)
        #expect(byte.value == 42)
    }

    @Test("MIXByte validation")
    func mixByteValidation() async {
        await #expect(processExitsWith: .failure) {
            _ = MIXByte(64)  // Exceeds 6-bit
        }
    }
}

// MARK: - MachineWord Protocol Tests

@Suite("MIX MachineWord Protocol Tests")
struct MIXMachineWordProtocolTests {
    @Test("MIXWord bitWidth")
    func mixWordBitWidth() {
        #expect(MIXWord.bitWidth == 30)
    }

    @Test("MIXWord storage access")
    func mixWordStorageAccess() {
        let word = MIXWord(sign: true, magnitude: 100)
        let storage = word.storage

        #expect(storage & 0x8000_0000 != 0)  // Sign bit set
        #expect(storage & 0x3FFF_FFFF == 100)  // Magnitude
    }

    @Test("MIXWord truncating init")
    func mixWordTruncatingInit() {
        let word = MIXWord(truncating: 0x4000_0000)  // Exceeds 30 bits
        #expect(word.magnitude == 0)  // Truncated
        #expect(!word.isNegative)
    }
}
