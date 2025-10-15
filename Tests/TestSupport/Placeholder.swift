import MMIXArchitecture
import MIXArchitecture
import MachineKit
import MachineRuntime

public enum TestFixtures {
    public static func sanityMessage() -> String {
        [MMIXArchitectureModule.bootstrap(),
         MIXArchitectureModule.bootstrap(),
         MachineKitPlaceholder.bootstrapSummary(),
         MachineRuntimePlaceholder.runtimeBanner()].joined(separator: " | ")
    }
}
