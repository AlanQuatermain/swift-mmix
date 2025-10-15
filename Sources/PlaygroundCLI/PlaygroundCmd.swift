import ArgumentParser
import MachineRuntime

@main
struct PlaygroundCLI: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Placeholder interactive playground for MIX/MMIX.")

    func run() throws {
        print("PlaygroundCLI stub – \(MachineRuntimePlaceholder.runtimeBanner())")
    }
}
