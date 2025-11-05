/// Marker protocol for MIX/MMIX word types.
///
/// Conforming types (e.g., `MIXWord`, `Octa`) will surface the raw
/// integer storage used by the underlying architecture while exposing
/// higher-level helpers for sign handling, masking, and field
/// extraction. Defining the contract here lets toolchain layers write
/// generic utilities without erasing architecture-specific fidelity.
public protocol MachineWord: Sendable {
    associatedtype Storage: FixedWidthInteger

    /// Bit width of the machine word (30 for MIX, 64 for MMIX, etc.).
    static var bitWidth: Int { get }

    /// Creates a value by truncating the supplied storage—useful when
    /// assembling partial fields or coercing immediates.
    init(truncating storage: Storage)

    /// Underlying representation used for serialization and math.
    var storage: Storage { get }
}

/// Shared interface for architecture-specific register files.
///
/// MIX and MMIX expose different register catalogs; the identifier
/// associated type stays opaque so higher layers can only interact
/// through domain-specific enums/wrappers supplied by the respective
/// architecture modules.
public protocol RegisterFile {
    associatedtype Word: MachineWord
    associatedtype RegisterIdentifier: Hashable

    /// Reads the current value of the specified register.
    func read(_ register: RegisterIdentifier) -> Word

    /// Writes a new value into the specified register.
    mutating func write(_ value: Word, to register: RegisterIdentifier)
}

/// Abstracts over MIX word-addressed memory and MMIX byte-addressed
/// memory while leaving architecture quirks to concrete types.
public protocol MemorySpace {
    associatedtype Address: Sendable
    associatedtype Word: MachineWord

    mutating func store(_ value: Word, at address: Address) throws
    func load(at address: Address) throws -> Word
}

// MARK: - Support Types

public enum ComparisonResult: Int, Sendable, Equatable {
    case less = -1
    case equal = 0
    case greater = 1
}
