import ArgumentParser
import MachineRuntime

@main
struct DebuggerCLI: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Placeholder MIX/MMIX debugger.")

    func run() throws {
        print("DebuggerCLI stub – \(MachineRuntimePlaceholder.runtimeBanner())")
    }
}
