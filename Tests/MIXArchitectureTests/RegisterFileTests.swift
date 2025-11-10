//
//  RegisterFileTests.swift
//  swift-mmix
//
//  MIX Register File Tests
//

import Testing
import MachineKit
@testable import MIXArchitecture

// MARK: - Basic Register Access

@Suite("MIX Register File - Basic Access")
struct MIXRegisterFileBasicTests {
    @Test("Initialize with zero values")
    func initializeZero() {
        let regFile = MIXRegisterFile()

        #expect(regFile.A == .positiveZero)
        #expect(regFile.X == .positiveZero)
        #expect(regFile.readIndex(1) == .positiveZero)
        #expect(regFile.J.value == 0)
        #expect(regFile.overflowToggle == false)
        #expect(regFile.comparisonIndicator == .equal)
    }

    @Test("Write and read A register")
    func writeReadA() {
        var regFile = MIXRegisterFile()

        let testWord = MIXWord(sign: false, bytes: [1, 2, 3, 4, 5])
        regFile.A = testWord

        #expect(regFile.A == testWord)
    }

    @Test("Write and read X register")
    func writeReadX() {
        var regFile = MIXRegisterFile()

        let testWord = MIXWord(sign: true, bytes: [10, 20, 30, 40, 50])
        regFile.X = testWord

        #expect(regFile.X == testWord)
    }

    @Test("Write and read J register")
    func writeReadJ() {
        var regFile = MIXRegisterFile()

        let testAddr = MIXAddress(1234)
        regFile.J = testAddr

        #expect(regFile.J.value == 1234)
    }
}

// MARK: - Index Registers

@Suite("MIX Register File - Index Registers")
struct MIXRegisterFileIndexTests {
    @Test("Read and write all six index registers")
    func readWriteAllIndices() {
        var regFile = MIXRegisterFile()

        for i in 1...6 {
            let testWord = MIXWord(sign: false, bytes: [0, 0, 0, UInt8(i * 10), UInt8(i)])
            regFile.writeIndex(testWord, to: i)

            let readBack = regFile.readIndex(i)
            #expect(readBack == testWord)
        }
    }

    @Test("Index register truncates to address field")
    func indexTruncation() {
        var regFile = MIXRegisterFile()

        // Create a full word with data in all bytes
        let fullWord = MIXWord(sign: true, bytes: [1, 2, 3, 4, 5])

        // Write to index register - should truncate to bytes 4:5
        regFile.writeIndex(fullWord, to: 1)

        let stored = regFile.readIndex(1)

        // Should only have bytes 4:5 and sign
        #expect(stored.isNegative == true)
        #expect(stored.bytes[0] == 0)
        #expect(stored.bytes[1] == 0)
        #expect(stored.bytes[2] == 0)
        #expect(stored.bytes[3] == 4)
        #expect(stored.bytes[4] == 5)
    }

    @Test("Index register preserves sign")
    func indexPreservesSign() {
        var regFile = MIXRegisterFile()

        let negativeWord = MIXWord(sign: true, bytes: [0, 0, 0, 10, 20])
        regFile.writeIndex(negativeWord, to: 3)

        let stored = regFile.readIndex(3)
        #expect(stored.isNegative == true)
    }
}

// MARK: - Flags and Indicators

@Suite("MIX Register File - Flags")
struct MIXRegisterFileFlagTests {
    @Test("Overflow toggle starts false")
    func overflowInitiallyFalse() {
        let regFile = MIXRegisterFile()
        #expect(regFile.overflowToggle == false)
    }

    @Test("Set overflow toggle")
    func setOverflowToggle() {
        var regFile = MIXRegisterFile()

        regFile.overflowToggle = true
        #expect(regFile.overflowToggle == true)
    }

    @Test("Clear overflow toggle")
    func clearOverflowToggle() {
        var regFile = MIXRegisterFile()

        regFile.overflowToggle = true
        regFile.overflowToggle = false

        #expect(regFile.overflowToggle == false)
    }

    @Test("Comparison indicator initially equal")
    func comparisonInitiallyEqual() {
        let regFile = MIXRegisterFile()
        #expect(regFile.comparisonIndicator == .equal)
    }

    @Test("Set comparison indicator to less")
    func comparisonLess() {
        var regFile = MIXRegisterFile()

        regFile.comparisonIndicator = .less
        #expect(regFile.comparisonIndicator == .less)
    }

    @Test("Set comparison indicator to greater")
    func comparisonGreater() {
        var regFile = MIXRegisterFile()

        regFile.comparisonIndicator = .greater
        #expect(regFile.comparisonIndicator == .greater)
    }
}

// MARK: - Effective Address Calculation

@Suite("MIX Register File - Effective Address")
struct MIXRegisterFileEffectiveAddressTests {
    @Test("No indexing (index = 0)")
    func noIndexing() {
        let regFile = MIXRegisterFile()

        let base = MIXAddress(1000)
        let ea = regFile.effectiveAddress(base: base, index: 0)

        #expect(ea.value == 1000)
    }

    @Test("Positive index offset")
    func positiveIndexOffset() {
        var regFile = MIXRegisterFile()

        // Set I1 to +50
        let indexWord = MIXWord(sign: false, bytes: [0, 0, 0, 0, 50])
        regFile.writeIndex(indexWord, to: 1)

        let base = MIXAddress(1000)
        let ea = regFile.effectiveAddress(base: base, index: 1)

        #expect(ea.value == 1050)
    }

    @Test("Negative index offset")
    func negativeIndexOffset() {
        var regFile = MIXRegisterFile()

        // Set I2 to -30
        let indexWord = MIXWord(sign: true, bytes: [0, 0, 0, 0, 30])
        regFile.writeIndex(indexWord, to: 2)

        let base = MIXAddress(1000)
        let ea = regFile.effectiveAddress(base: base, index: 2)

        #expect(ea.value == 970)
    }

    @Test("Address wraparound modulo 4000")
    func addressWraparound() {
        var regFile = MIXRegisterFile()

        // Set I3 to a large positive value that will wrap
        // 4090 + 10 = 4100, which wraps to 4100 % 4000 = 100
        let indexWord = MIXWord(sign: false, bytes: [0, 0, 0, 0, 10])
        regFile.writeIndex(indexWord, to: 3)

        let base = MIXAddress(4090)
        let ea = regFile.effectiveAddress(base: base, index: 3)

        #expect(ea.value == 100)
    }

    @Test("All six index registers")
    func allSixIndices() {
        var regFile = MIXRegisterFile()

        let base = MIXAddress(1000)

        for i in 1...6 {
            // Set each index register to different offset
            let offset = UInt8(i * 10)
            let indexWord = MIXWord(sign: false, bytes: [0, 0, 0, 0, offset])
            regFile.writeIndex(indexWord, to: i)

            let ea = regFile.effectiveAddress(base: base, index: i)
            #expect(ea.value == 1000 + UInt16(offset))
        }
    }

    @Test("Index offset returns signed value")
    func indexOffset() {
        var regFile = MIXRegisterFile()

        // Positive offset
        let positiveWord = MIXWord(sign: false, bytes: [0, 0, 0, 0, 50])
        regFile.writeIndex(positiveWord, to: 1)
        #expect(regFile.indexOffset(1) == 50)

        // Negative offset
        let negativeWord = MIXWord(sign: true, bytes: [0, 0, 0, 0, 30])
        regFile.writeIndex(negativeWord, to: 2)
        #expect(regFile.indexOffset(2) == -30)

        // Zero index returns 0
        #expect(regFile.indexOffset(0) == 0)
    }
}

// MARK: - MachineKit Protocol

@Suite("MIX Register File - Protocol Conformance")
struct MIXRegisterFileProtocolTests {
    @Test("Read A via protocol")
    func readAViaProtocol() {
        var regFile = MIXRegisterFile()

        let testWord = MIXWord(sign: false, bytes: [1, 2, 3, 4, 5])
        regFile.A = testWord

        let value = regFile.read(.A)
        #expect(value == testWord)
    }

    @Test("Write A via protocol")
    func writeAViaProtocol() {
        var regFile = MIXRegisterFile()

        let testWord = MIXWord(sign: true, bytes: [5, 4, 3, 2, 1])
        regFile.write(testWord, to: .A)

        #expect(regFile.A == testWord)
    }

    @Test("Read X via protocol")
    func readXViaProtocol() {
        var regFile = MIXRegisterFile()

        let testWord = MIXWord(sign: false, bytes: [10, 20, 30, 40, 50])
        regFile.X = testWord

        let value = regFile.read(.X)
        #expect(value == testWord)
    }

    @Test("Write X via protocol")
    func writeXViaProtocol() {
        var regFile = MIXRegisterFile()

        let testWord = MIXWord(sign: true, bytes: [50, 40, 30, 20, 10])
        regFile.write(testWord, to: .X)

        #expect(regFile.X == testWord)
    }

    @Test("Read index via protocol")
    func readIndexViaProtocol() {
        var regFile = MIXRegisterFile()

        let testWord = MIXWord(sign: false, bytes: [0, 0, 0, 12, 34])
        regFile.writeIndex(testWord, to: 4)

        let value = regFile.read(.index(4))
        #expect(value == testWord)
    }

    @Test("Write index via protocol")
    func writeIndexViaProtocol() {
        var regFile = MIXRegisterFile()

        let testWord = MIXWord(sign: true, bytes: [0, 0, 0, 56, 63])
        regFile.write(testWord, to: .index(5))

        #expect(regFile.readIndex(5) == testWord)
    }

    @Test("Read J via protocol")
    func readJViaProtocol() {
        var regFile = MIXRegisterFile()

        regFile.J = MIXAddress(2000)

        let value = regFile.read(.J)
        let addr = MIXAddress(fromWord: value)
        #expect(addr.value == 2000)
    }

    @Test("Write J via protocol")
    func writeJViaProtocol() {
        var regFile = MIXRegisterFile()

        let addr = MIXAddress(3000)
        regFile.write(addr.asWord, to: .J)

        #expect(regFile.J.value == 3000)
    }
}

// MARK: - Debugging Support

@Suite("MIX Register File - Debugging")
struct MIXRegisterFileDebuggingTests {
    @Test("CustomStringConvertible produces output")
    func stringDescription() {
        var regFile = MIXRegisterFile()

        regFile.A = MIXWord(sign: false, bytes: [1, 2, 3, 4, 5])
        regFile.X = MIXWord(sign: true, bytes: [5, 4, 3, 2, 1])
        regFile.overflowToggle = true
        regFile.comparisonIndicator = .greater

        let description = regFile.description

        // Should contain register values
        #expect(description.contains("A:"))
        #expect(description.contains("X:"))
        #expect(description.contains("J:"))
        #expect(description.contains("OV:"))
        #expect(description.contains("CMP:"))
    }
}

// MARK: - Edge Cases

@Suite("MIX Register File - Edge Cases")
struct MIXRegisterFileEdgeCaseTests {
    @Test("Maximum address value")
    func maxAddress() {
        var regFile = MIXRegisterFile()

        let maxAddr = MIXAddress(4095)  // 12-bit max
        regFile.J = maxAddr

        #expect(regFile.J.value == 4095)
    }

    @Test("Large index causing wraparound")
    func largeIndexWraparound() {
        var regFile = MIXRegisterFile()

        // Set large index value (bytes 4:5 can hold 0-4095)
        let largeIndex = MIXWord(sign: false, bytes: [0, 0, 0, 0x3F, 0x3F])  // 4095
        regFile.writeIndex(largeIndex, to: 1)

        let base = MIXAddress(10)
        let ea = regFile.effectiveAddress(base: base, index: 1)

        // (10 + 4095) % 4000 = 105
        #expect(ea.value == 105)
    }

    @Test("Negative index causing underflow and wrap")
    func negativeIndexUnderflow() {
        var regFile = MIXRegisterFile()

        // Set negative index
        let negIndex = MIXWord(sign: true, bytes: [0, 0, 0, 0, 50])
        regFile.writeIndex(negIndex, to: 2)

        let base = MIXAddress(10)
        let ea = regFile.effectiveAddress(base: base, index: 2)

        // (10 - 50) % 4000 = 3960 (wraps around)
        let expected = (4000 + 10 - 50) % 4000
        #expect(ea.value == UInt16(expected))
    }

    @Test("All registers can be set independently")
    func allRegistersIndependent() {
        var regFile = MIXRegisterFile()

        regFile.A = MIXWord(sign: false, bytes: [1, 1, 1, 1, 1])
        regFile.X = MIXWord(sign: false, bytes: [2, 2, 2, 2, 2])

        for i in 1...6 {
            let word = MIXWord(sign: false, bytes: [0, 0, 0, UInt8(i), UInt8(i)])
            regFile.writeIndex(word, to: i)
        }

        regFile.J = MIXAddress(999)
        regFile.overflowToggle = true
        regFile.comparisonIndicator = .less

        // Verify all still have correct values
        #expect(regFile.A.bytes[0] == 1)
        #expect(regFile.X.bytes[0] == 2)

        for i in 1...6 {
            let stored = regFile.readIndex(i)
            #expect(stored.bytes[3] == UInt8(i))
        }

        #expect(regFile.J.value == 999)
        #expect(regFile.overflowToggle == true)
        #expect(regFile.comparisonIndicator == .less)
    }
}
