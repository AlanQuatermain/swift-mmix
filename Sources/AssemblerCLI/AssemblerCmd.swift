import ArgumentParser
import MachineKit

@main
struct AssemblerCLI: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Placeholder MIX/MMIX assembler.")

    func run() throws {
        print("Hello")
    }
}
