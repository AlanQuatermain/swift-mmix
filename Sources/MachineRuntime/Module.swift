import MachineKit

public enum MachineRuntimePlaceholder {
    public static func runtimeBanner() -> String {
        "Runtime ready: \(MachineKitPlaceholder.bootstrapSummary())"
    }
}
