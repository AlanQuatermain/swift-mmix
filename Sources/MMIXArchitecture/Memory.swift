//
//  Memory.swift
//  swift-mmix
//
//  Created by Jim Dovey on 10/14/25.
//

import MachineKit

/// MMIX Memory - Byte-addressable with sparse page-based storage.
///
/// ### Architecture
///
/// - 2^64 byte address space
/// - Byte-addressable (M[k] is a byte)
/// - Big-endian multi-byte loads
/// - Alignment requirements (optional, trap if violated)
/// - Page-based sparse allocation.
public struct MMIXMemory: @unchecked Sendable {
    /// Page size (4KB standard)
    public static let pageSize: UInt64 = 4096
    /// Bit-shift for page size determination.
    public static let pageShift: UInt64 = 12
    /// Page mask.
    public static let pageMask: UInt64 = 0xFFF

    /// Page storage (page base address -> page data)
    private var pages: [UInt64: UnsafeMutableRawBufferPointer]

    /// Alignment checking enabled.
    public var checkAlignment: Bool

    // MARK: Initialization

    public init(checkAlignment: Bool = true) {
        self.pages = [:]
        self.checkAlignment = checkAlignment
    }

    // MARK: Page Management

    /// Get page base and offset for address.
    private func pageAddress(_ address: UInt64) -> (base: UInt64, offset: Int) {
        let base = address & Self.pageMask
        let offset = Int(address & ~Self.pageMask)
        return (base, offset)
    }

    /// Get page base and offset for address, overloaded for Octa input.
    private func pageAddress(_ address: Octa) -> (base: UInt64, offset: Int) {
        pageAddress(address.storage)
    }

    /// Ensure page exists for address.
    @discardableResult
    private mutating func ensurePage(
        for address: UInt64
    ) -> UnsafeMutableRawBufferPointer {
        let (base, _) = pageAddress(address)
        if pages[base] == nil {
            pages[base] = .allocate(
                byteCount: Int(Self.pageSize), alignment: 8)
        }
        return pages[base].unsafelyUnwrapped
    }

    // MARK: Byte Operations

    /// Load byte at address.
    public func loadByte(at address: Octa) -> Byte {
        let (base, offset) = pageAddress(address)
        guard let page = pages[base] else {
            return Byte(0)  // Unallocated memory reads as 0 (lenient mode)
        }
        return Byte(page[offset])
    }

    /// Store byte at address.
    public mutating func storeByte(_ value: Byte, at address: Octa) {
        let page = ensurePage(for: address.storage)
        let (_, offset) = pageAddress(address)
        page[offset] = value.storage
    }

    // MARK: Multi-byte Operations

    /// Load wyde (2 bytes) at address.
    public func loadWyde(at address: Octa) throws(MemoryError) -> Wyde {
        guard !checkAlignment || (address.storage % 2 == 0) else {
            throw MemoryError.misaligned(address: address, required: 2)
        }

        let (base, offset) = pageAddress(address)
        guard let page = pages[base] else {
            return Wyde(0)  // Lenient mode - return 0
        }

        // If we require alignment, we can use Swift casts, which also require
        // alignment
        let val = if checkAlignment {
            page.load(fromByteOffset: offset, as: UInt16.self)
        } else {
            page.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
        }
        return Wyde(val)
    }

    /// Store wyde (2 bytes) at address.
    public mutating func storeWyde(
        _ value: Wyde, at address: Octa
    ) throws(MemoryError) {
        guard !checkAlignment || (address.storage % 2 == 0) else {
            throw MemoryError.misaligned(address: address, required: 2)
        }

        let page = ensurePage(for: address.storage)
        let (_, offset) = pageAddress(address)
        page.storeBytes(of: value.storage, toByteOffset: offset, as: UInt16.self)
    }

    /// Load tetra (4 bytes) at address.
    public func loadTetra(
        at address: Octa
    ) throws(MemoryError) -> Tetra {
        guard !checkAlignment || (address.storage % 4 == 0) else {
            throw MemoryError.misaligned(address: address, required: 4)
        }

        let (base, offset) = pageAddress(address)
        guard let page = pages[base] else {
            return Tetra(0)  // Lenient mode - return 0
        }

        // If we require alignment, we can use Swift casts, which also require
        // alignment
        let val = if checkAlignment {
            page.load(fromByteOffset: offset, as: UInt32.self)
        } else {
            page.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
        return Tetra(val)
    }

    /// Store tetra (4 bytes) at address.
    public mutating func storeTetra(
        _ value: Tetra, at address: Octa
    ) throws(MemoryError) {
        guard !checkAlignment || (address.storage % 4 == 0) else {
            throw MemoryError.misaligned(address: address, required: 4)
        }

        let page = ensurePage(for: address.storage)
        let (_, offset) = pageAddress(address)
        page.storeBytes(of: value.storage, toByteOffset: offset, as: UInt32.self)
    }

    /// Load octa (8 bytes) at address.
    public func loadOcta(
        at address: Octa
    ) throws(MemoryError) -> Octa {
        guard !checkAlignment || (address.storage % 8 == 0) else {
            throw MemoryError.misaligned(address: address, required: 8)
        }

        let (base, offset) = pageAddress(address)
        guard let page = pages[base] else {
            return Octa(0)  // Lenient mode - return 0
        }

        // If we require alignment, we can use Swift casts, which also require
        // alignment
        let val = if checkAlignment {
            page.load(fromByteOffset: offset, as: UInt64.self)
        } else {
            page.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
        }
        return Octa(val)
    }

    /// Store octa (8 bytes) at address.
    public mutating func storeOcta(
        _ value: Octa, at address: Octa
    ) throws(MemoryError) {
        guard !checkAlignment || (address.storage % 8 == 0) else {
            throw MemoryError.misaligned(address: address, required: 8)
        }

        let page = ensurePage(for: address.storage)
        let (_, offset) = pageAddress(address)
        page.storeBytes(of: value.storage, toByteOffset: offset, as: UInt64.self)
    }

    // MARK: Bulk Operations

    /// Load program image at base address.
    public mutating func loadImage(
        at baseAddress: Octa, data: UnsafeRawBufferPointer
    ) {
        var countDown = data.count
        var (base, offset) = pageAddress(baseAddress)
        var dataOffset = 0
        let pageSize = Int(Self.pageSize)
        repeat {
            let page = ensurePage(for: base)

            if offset != 0 {
                let toCopy = pageSize - offset
                let subPage = UnsafeMutableRawBufferPointer(rebasing: page[offset...])
                subPage.copyMemory(from: .init(rebasing: data[dataOffset..<toCopy]))
                dataOffset += toCopy
                countDown -= toCopy
            } else if countDown < pageSize {
                // Last few bytes get copied into the start of this page
                page.copyMemory(from: .init(rebasing: data[dataOffset...]))
                dataOffset += countDown
                countDown = 0
            } else {
                // Copy an entire page
                page.copyMemory(from: .init(rebasing: data[dataOffset..<(dataOffset + Int(Self.pageSize))]))
                dataOffset += pageSize
                countDown -= pageSize
            }

            base += UInt64(pageSize)
            offset = 0
        } while countDown > 0
    }

    /// Dump memory range as bytes.
    public func dump(from start: Octa, count: Int) -> [UInt8] {
        var output = [UInt8]()
        output.reserveCapacity(count)

        var countDown = count
        var (base, offset) = pageAddress(start)
        let pageSize = Int(Self.pageSize)
        repeat {
            let amount = pageSize - offset
            if let page = pages[base] {
                output.append(contentsOf: page[offset..<amount])
            } else {
                output.append(contentsOf: repeatElement(UInt8(0), count: amount))
            }
            countDown -= amount
            base += 1
        } while countDown > 0

        return output
    }

    public var allocatedPages: Int {
        pages.count
    }

    public var allocatedBytes: Int {
        allocatedPages * Int(Self.pageSize)
    }
}

// MARK: - Error Types

public enum MemoryError: Error, Sendable {
    case misaligned(address: Octa, required: Int)
    case outOfBounds(address: Octa)
    case deviceFault(address: Octa, message: String)
}

// MARK: - MachineKit Protocol Conformance

extension MMIXMemory: MemorySpace {
    public typealias Address = Octa
    public typealias Word = Octa

    public mutating func store(_ value: Octa, at address: Octa) throws {
        try storeOcta(value, at: address)
    }

    public func load(at address: Octa) throws -> Octa {
        try loadOcta(at: address)
    }
}
