//
//  Memory.swift
//  swift-mmix
//
//  Created by Jim Dovey on 10/14/25.
//

import MachineKit

/// MIX Memory - Word-addressable storage.
///
/// ### Architecture
///
/// - 4000 words by default (addresses 0–3999)
/// - Each word is 5 bytes + sign
/// - Field-aware load/store operations
/// - No alignment requirements (word-granular)
public struct MIXMemory: Sendable {
    private var storage: ContiguousArray<MIXWord>

    /// Memory size in words.
    public let size: Int

    // MARK: Initialization

    public init(size: Int = 4000) {
        precondition((1...4096).contains(size), "MIX memory size must be 1...4096")
        self.size = size
        self.storage = .init(repeating: .positiveZero, count: size)
    }

    // MARK: Address Normalization

    /// Normalize address to valid range (with wrapping).
    private func normalizeAddress(_ address: UInt16) -> Int {
        Int(address) % size
    }

    // MARK: Load Operations

    /// Load word with field specification (Memory -> Register).
    ///
    /// ### Semantics
    ///
    /// - Reads bytes at memory positions L:R within addressed word
    /// - Returns MIXWord with bytes *right-aligned*
    /// - Unused leading bytes filled with zeroes
    /// - Sign copied ONLY if L=0, else result is positive
    ///
    /// Example:
    ///
    ///     Memory = + 10 20 30 40 50
    ///     Load = field (2:3)
    ///     Result = + 00 00 00 20 30
    public func load(at address: UInt16, field: FieldSpec = .full) -> MIXWord {
        let addr = normalizeAddress(address)
        let memWord = storage[addr]

        // Handle simplest case.
        guard field == .full else { return memWord }

        // Extract sign if field includes it
        let sign = field.includesSign ? memWord.isNegative : false

        // Extract bytes from memory positions L:R
        var resultBytes: [UInt8] = [0, 0, 0, 0, 0]
        let startByte = max(Int(field.left), 1)
        let endByte = max(Int(field.right), 1)

        // Copy bytes from memory positions, right-align in result
        let byteCount = endByte - startByte + 1
        let destStart = 5 - byteCount + 1

        for i in 0..<byteCount {
            resultBytes[destStart + i] = memWord[startByte + i]
        }

        return MIXWord(sign: sign, bytes: resultBytes)
    }

    /// Load full word (no field extraction).
    public func loadFull(at address: UInt16) -> MIXWord {
        let addr = normalizeAddress(address)
        return storage[addr]
    }

    // MARK: Store Operations

    /// Store word with field specification (Register -> Memory)
    ///
    /// ### Semantics
    ///
    /// - Reads *rightmost* (R-L+1) bytes from register value
    /// - Writes to memory positions L:R
    /// - Other memory bytes preserved
    /// - Sign replaced **only** if L=0, else memory sign unchanged
    ///
    /// Example:
    ///
    ///     Register = - 01 02 03 04 05
    ///     Memory = + 10 20 30 40 50
    ///     Store = field (2:3)
    ///     Result = + 10 04 05 40 50
    public mutating func store(
        _ value: MIXWord, at address: UInt16, field: FieldSpec = .full
    ) {
        let addr = normalizeAddress(address)

        // Simple case
        guard field != .full else {
            storage[addr] = value
            return
        }

        var memWord = storage[addr]

        // Replace sign if field includes it
        if field.includesSign {
            memWord.isNegative = value.isNegative
        }

        // Replace bytes at memory positions L:R with least-significant R-L
        // bytes from source register value.
        let startByte = max(Int(field.left), 1)
        let endByte = max(Int(field.right), 1)
        let byteCount = endByte - startByte + 1

        // Source from rightmost bytes of register
        let srcStart = 5 - byteCount + 1
        for i in 0..<byteCount {
            memWord[startByte + i] = value[srcStart + i]
        }

        storage[addr] = memWord
    }

    /// Store full word (replaces entire word).
    public mutating func storeFull(_ value: MIXWord, at address: UInt16) {
        let addr = normalizeAddress(address)
        storage[addr] = value
    }

    // MARK: Bulk Operations

    /// Load program starting at address.
    public mutating func loadProgram(at address: UInt16, words: some Collection<MIXWord>) {
        let startAddr = Int(normalizeAddress(address))
        let len = words.count
        storage.withUnsafeMutableBufferPointer { mem in
            let target = mem.extracting(startAddr..<startAddr+len)
            _ = target.update(fromContentsOf: words)
        }
    }

    /// Load from an array of encoded words.
    public mutating func loadImage(
        at address: UInt16, image: [(sign: Bool, bytes: [UInt8])]
    ) {
        var addr = Int(address)
        for (sign, bytes) in image {
            storage[addr % size] = MIXWord(sign: sign, bytes: bytes)
            addr += 1
        }
    }

    /// Dump memory range.
    public func dump(from start: UInt16, count: Int) -> [MIXWord] {
        let addr = Int(start)
        return Array(storage[addr..<addr+count])
    }

    /// Clear all memory to +0.
    public mutating func clear() {
        storage = ContiguousArray(repeating: .positiveZero, count: size)
    }

    /// Clear range to +0.
    public mutating func clearRange(from start: UInt16, count: Int) {
        var addr = Int(start)
        storage.withUnsafeMutableBufferPointer { buf in
            let target = buf.extracting(addr..<addr+count)
            target.initialize(repeating: .positiveZero)
        }
    }
}

// MARK: - MachineKit Protocol Conformance

extension MIXMemory: MemorySpace {
    public typealias Address = UInt16
    public typealias Word = MIXWord

    public mutating func store(_ value: MIXWord, at address: UInt16) throws {
        storeFull(value, at: address)
    }

    public func load(at address: UInt16) throws -> MIXWord {
        loadFull(at: address)
    }
}

// MARK: - Debugging Support

extension MIXMemory: CustomStringConvertible {
    public var description: String {
        "MIX Memory [\(size) words]"
    }
}
