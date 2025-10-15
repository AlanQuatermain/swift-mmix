/// Namespace for MIX-specific numeric and register definitions.
///
/// MIX words follow the TAoCP sign-plus-five-6-bit-bytes layout,
/// requiring sign-magnitude arithmetic and field-spec aware slicing.
/// Keeping the module distinct from MMIX preserves clarity between the
/// word-addressed MIX machine and the byte-addressed MMIX world.
public enum MIXArchitectureModule {
    public static let identifier = "MIXArchitecture"

    public static func bootstrap() -> String {
        identifier
    }
}
