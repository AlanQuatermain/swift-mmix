//
//  RegisterFileTests.swift
//  swift-mmix
//
//  MMIX Register File Tests
//

import Testing
import MachineKit
@testable import MMIXArchitecture

// MARK: - Basic Register Access

@Suite("MMIX Register File - Basic Access")
struct MMIXRegisterFileBasicTests {
    @Test("$0 hardwired to zero - reads always return 0")
    func dollarZeroReadsZero() {
        let regFile = MMIXRegisterFile(L: 10, G: 200)
        #expect(regFile.readGeneral(0) == .zero)
    }

    @Test("$0 hardwired to zero - writes are ignored")
    func dollarZeroWritesIgnored() {
        var regFile = MMIXRegisterFile(L: 10, G: 200)
        regFile.writeGeneral(Octa(42), to: 0)
        #expect(regFile.readGeneral(0) == .zero)
    }

    @Test("Write and read local register")
    func writeReadLocal() {
        var regFile = MMIXRegisterFile(L: 10, G: 200)
        let testValue = Octa(12345)

        regFile.writeGeneral(testValue, to: 5)
        #expect(regFile.readGeneral(5) == testValue)
    }

    @Test("Write and read global register")
    func writeReadGlobal() {
        var regFile = MMIXRegisterFile(L: 10, G: 200)
        let testValue = Octa(0xDEADBEEF)

        regFile.writeGeneral(testValue, to: 220)
        #expect(regFile.readGeneral(220) == testValue)
    }

    @Test("Global registers at fixed positions")
    func globalRegistersFixed() {
        var regFile = MMIXRegisterFile(L: 10, G: 200)

        // Write to global
        regFile.writeGeneral(Octa(100), to: 250)

        // Push frame (changes rO)
        _ = regFile.pushFrame()

        // Global should still be at same physical position
        #expect(regFile.readGeneral(250) == Octa(100))
    }
}

// MARK: - Local/Marginal/Global Zones

@Suite("MMIX Register File - Zones")
struct MMIXRegisterFileZoneTests {
    @Test("Reading marginal registers returns 0")
    func marginalReadsZero() {
        let regFile = MMIXRegisterFile(L: 10, G: 200)

        // Registers 10-199 are marginal, should read as 0
        #expect(regFile.readGeneral(15) == .zero)
        #expect(regFile.readGeneral(100) == .zero)
        #expect(regFile.readGeneral(199) == .zero)
    }

    @Test("Writing to marginal promotes to local and grows rL")
    func marginalWritePromotes() {
        var regFile = MMIXRegisterFile(L: 5, G: 200)

        // Write to marginal register index 10
        regFile.writeGeneral(Octa(42), to: 10)

        let (_, _, rL, _) = regFile.stackState()
        #expect(rL == 11)  // Promoted through index 10
        #expect(regFile.readGeneral(10) == Octa(42))
    }

    @Test("Writing to marginal clears intervening registers")
    func marginalWriteClearsIntervening() {
        var regFile = MMIXRegisterFile(L: 5, G: 200)

        // Write some locals first
        regFile.writeGeneral(Octa(1), to: 1)
        regFile.writeGeneral(Octa(2), to: 2)

        // Write to marginal at index 10 (skipping 5-9)
        regFile.writeGeneral(Octa(100), to: 10)

        // Indices 5-9 should be zero
        #expect(regFile.readGeneral(5) == .zero)
        #expect(regFile.readGeneral(9) == .zero)

        // Index 10 should have our value
        #expect(regFile.readGeneral(10) == Octa(100))
    }
}

// MARK: - Special Registers

@Suite("MMIX Register File - Special Registers")
struct MMIXRegisterFileSpecialTests {
    @Test("Read and write special registers")
    func specialRegisterAccess() {
        var regFile = MMIXRegisterFile(L: 10, G: 200)

        regFile.writeSpecial(Octa(0x1234), to: .rA)
        #expect(regFile.readSpecial(.rA) == Octa(0x1234))

        regFile.writeSpecial(Octa(0x5678), to: .rH)
        #expect(regFile.readSpecial(.rH) == Octa(0x5678))
    }

    @Test("Writing rS adjusts memory stack size")
    func rSAdjustsMemoryStack() {
        var regFile = MMIXRegisterFile(L: 10, G: 200)

        // Write rS to indicate 5 octabytes on stack
        regFile.writeSpecial(Octa(40), to: .rS)  // 5 * 8 = 40

        let (_, rS, _, _) = regFile.stackState()
        #expect(rS == 40)
    }
}

// MARK: - Ring Buffer Mechanics (Required Test Cases)

@Suite("MMIX Register File - Ring Buffer α/β/γ")
struct MMIXRegisterFileRingBufferTests {
    @Test("Growth without spill")
    func growthWithoutSpill() {
        var regFile = MMIXRegisterFile(L: 0, G: 128)
        // rO=0, rS=0 by default

        // Grow by 10 by writing to marginal register at index 9
        regFile.writeGeneral(Octa(42), to: 9)

        let (_, rS, rL, _) = regFile.stackState()
        let (_, beta, gamma) = regFile.ringPointers()

        #expect(rS == 0, "No spill should occur, rS should remain 0")
        #expect(beta == 10, "Beta should advance to 10")
        #expect(gamma == 0, "Gamma should remain at 0")
        #expect(rL == 10, "rL should be 10 after growth")
    }

    @Test("Spill boundary")
    func spillBoundary() {
        var regFile = MMIXRegisterFile(L: 127, G: 128)
        // rO=0, rS=0 by default

        // Grow by 1 by writing to marginal register at index 127
        regFile.writeGeneral(Octa(100), to: 127)

        let (_, rS, rL, _) = regFile.stackState()
        let (_, beta, gamma) = regFile.ringPointers()

        #expect(rS == 8, "One register spilled, rS should be 8")
        #expect(rL == 128, "rL should be 128 after growth")
        #expect(beta == (128 % rL), "Beta should wrap correctly")
        #expect(gamma == 1, "Gamma should advance by 1")
    }

    @Test("Wrap and spill")
    func wrapAndSpill() {
        var regFile = MMIXRegisterFile(L: 0, G: 128)

        // Set rO to near the end of the ring
        regFile.writeSpecial(Octa(127 * 8), to: .rO)

        let initialRS = regFile.stackState().rS

        // Grow by writing to marginal registers up to 127
        // This will wrap around and require spills
        for i in 1..<128 {
            regFile.writeGeneral(Octa(UInt64(i)), to: i)
        }

        let (_, finalRS, rL, _) = regFile.stackState()
        let (_, beta, gamma) = regFile.ringPointers()

        #expect(rL == 128, "rL should be 128 after growth")
        #expect(finalRS > initialRS, "Spills should have occurred")
        #expect(beta != gamma, "Beta should never equal gamma")
    }

    @Test("Fill on pop")
    func fillOnPop() {
        var regFile = MMIXRegisterFile(L: 0, G: 128)

        // Set rO to near the end, similar to "wrap and spill" test
        regFile.writeSpecial(Octa(127 * 8), to: .rO)

        // Grow - will spill
        for i in 1..<128 {
            regFile.writeGeneral(Octa(UInt64(i)), to: i)
        }

        let spilledRS = regFile.stackState().rS

        // Push a frame to move forward
        let savedL = regFile.pushFrame()

        // Now pop back - should trigger fills
        regFile.popFrame(ofSize: savedL)

        let (_, finalRS, _, _) = regFile.stackState()

        #expect(finalRS < spilledRS, "rS should decrease after fills during pop")
        #expect(spilledRS > 0, "We should have spilled before filling")
    }
}

// MARK: - Frame Push/Pop

@Suite("MMIX Register File - Frame Operations")
struct MMIXRegisterFileFrameTests {
    @Test("pushFrame slides window forward")
    func pushFrameSlidesForward() {
        var regFile = MMIXRegisterFile(L: 10, G: 200)

        let initialRO = regFile.stackState().rO

        let savedL = regFile.pushFrame()

        let finalRO = regFile.stackState().rO

        #expect(savedL == 10)
        #expect(finalRO == initialRO + (10 * 8))
    }

    @Test("pushFrame and popFrame round-trip")
    func pushPopRoundTrip() {
        var regFile = MMIXRegisterFile(L: 15, G: 200)

        // Write some values to locals
        for i in 0..<15 {
            regFile.writeGeneral(Octa(UInt64(i * 100)), to: i)
        }

        let (initialRO, _, initialRL, _) = regFile.stackState()

        // Push frame
        let savedL = regFile.pushFrame()

        // Pop frame
        regFile.popFrame(ofSize: savedL)

        let (finalRO, _, finalRL, _) = regFile.stackState()

        #expect(finalRO == initialRO)
        #expect(finalRL == initialRL)
    }

    @Test("Multiple nested frames")
    func multipleNestedFrames() {
        var regFile = MMIXRegisterFile(L: 10, G: 200)

        // Push first frame
        let frame1L = regFile.pushFrame()
        regFile.writeSpecial(Octa(5), to: .rL)

        // Push second frame
        let frame2L = regFile.pushFrame()
        regFile.writeSpecial(Octa(7), to: .rL)

        // Push third frame
        let frame3L = regFile.pushFrame()

        // Now pop them in reverse order
        regFile.popFrame(ofSize: frame3L)
        regFile.popFrame(ofSize: frame2L)
        regFile.popFrame(ofSize: frame1L)

        // Should be back to original state
        let (rO, _, rL, _) = regFile.stackState()
        #expect(rO == 0)
        #expect(rL == 10)
    }
}

// MARK: - Ring Wraparound

@Suite("MMIX Register File - Wraparound")
struct MMIXRegisterFileWraparoundTests {
    @Test("Alpha wraps past rG")
    func alphaWraps() {
        var regFile = MMIXRegisterFile(L: 10, G: 200)

        // Set rO to near the end
        regFile.writeSpecial(Octa(195 * 8), to: .rO)

        let (alpha1, _, _) = regFile.ringPointers()
        #expect(alpha1 == 195)

        // Push frame - should wrap alpha
        _ = regFile.pushFrame()

        let (alpha2, _, _) = regFile.ringPointers()
        // Alpha should wrap: (195 + 10) % 200 = 5
        #expect(alpha2 == 5)
    }

    @Test("Beta calculation handles wraparound")
    func betaWraps() {
        var regFile = MMIXRegisterFile(L: 20, G: 200)

        // Set rO so alpha + rL will wrap
        regFile.writeSpecial(Octa(195 * 8), to: .rO)

        let (alpha, beta, _) = regFile.ringPointers()

        #expect(alpha == 195)
        // Beta = (195 + 20) % 200 = 15
        #expect(beta == 15)
    }
}

// MARK: - Edge Cases

@Suite("MMIX Register File - Edge Cases")
struct MMIXRegisterFileEdgeCaseTests {
    @Test("rL = 0 (no locals)")
    func noLocals() {
        let regFile = MMIXRegisterFile(L: 0, G: 200)

        let (_, _, rL, _) = regFile.stackState()
        #expect(rL == 0)

        // All registers 0-199 should be marginal (read as 0)
        #expect(regFile.readGeneral(0) == .zero)
        #expect(regFile.readGeneral(100) == .zero)
    }

    @Test("rL = rG (all non-globals are local)")
    func allNonGlobalsLocal() {
        var regFile = MMIXRegisterFile(L: 200, G: 200)

        // Write to register just before G
        regFile.writeGeneral(Octa(42), to: 199)
        #expect(regFile.readGeneral(199) == Octa(42))

        // No marginal zone
        let (_, _, rL, rG) = regFile.stackState()
        #expect(rL == rG)
    }

    @Test("Deep nesting with spills and fills")
    func deepNesting() {
        var regFile = MMIXRegisterFile(L: 20, G: 100)

        // Push multiple frames to force spills
        var frameSizes: [Int] = []

        for i in 1...10 {
            frameSizes.append(regFile.stackState().rL)
            _ = regFile.pushFrame()

            // Set new rL for next frame
            regFile.writeSpecial(Octa(UInt64(15 + i)), to: .rL)
        }

        // Pop them all back
        for frameSize in frameSizes.reversed() {
            regFile.popFrame(ofSize: frameSize)
        }

        // Should be back to original
        let (rO, rS, rL, _) = regFile.stackState()
        #expect(rO == 0)
        #expect(rS == 0)
        #expect(rL == 20)
    }
}

// MARK: - MachineKit Protocol

@Suite("MMIX Register File - Protocol Conformance")
struct MMIXRegisterFileProtocolTests {
    @Test("Read general register via protocol")
    func readViaProtocol() {
        var regFile = MMIXRegisterFile(L: 10, G: 200)

        regFile.writeGeneral(Octa(0x1234), to: 5)

        let value = regFile.read(.general(5))
        #expect(value == Octa(0x1234))
    }

    @Test("Write general register via protocol")
    func writeViaProtocol() {
        var regFile = MMIXRegisterFile(L: 10, G: 200)

        regFile.write(Octa(0xABCD), to: .general(7))

        #expect(regFile.readGeneral(7) == Octa(0xABCD))
    }

    @Test("Read special register via protocol")
    func readSpecialViaProtocol() {
        var regFile = MMIXRegisterFile(L: 10, G: 200)

        regFile.writeSpecial(Octa(100), to: .rA)

        let value = regFile.read(.special(.rA))
        #expect(value == Octa(100))
    }

    @Test("Write special register via protocol")
    func writeSpecialViaProtocol() {
        var regFile = MMIXRegisterFile(L: 10, G: 200)

        regFile.write(Octa(200), to: .special(.rH))

        #expect(regFile.readSpecial(.rH) == Octa(200))
    }
}
