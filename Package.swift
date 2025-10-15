// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-mmix",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(
            name: "MMIXArchitecture",
            targets: ["MMIXArchitecture"]
        ),
        .library(
            name: "MIXArchitecture",
            targets: ["MIXArchitecture"]
        ),
        .library(
            name: "MachineKit",
            targets: ["MachineKit"]
        ),
        .library(
            name: "MachineRuntime",
            targets: ["MachineRuntime"]
        ),
        .executable(
            name: "mx-asm",
            targets: ["AssemblerCLI"]
        ),
        .executable(
            name: "mx-dbg",
            targets: ["DebuggerCLI"]
        ),
        .executable(
            name: "mx-playground",
            targets: ["PlaygroundCLI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing", from: "6.2.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "MMIXArchitecture",
            dependencies: [
                "MachineKit",
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .target(
            name: "MIXArchitecture",
            dependencies: [
                "MachineKit",
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .target(
            name: "MachineKit",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .target(
            name: "MachineRuntime",
            dependencies: [
                "MachineKit", "MMIXArchitecture", "MIXArchitecture",
                .product(name: "Logging", package: "swift-log")
            ]
        ),

        .executableTarget(
            name: "AssemblerCLI",
            dependencies: [
                "MachineKit", "MIXArchitecture", "MMIXArchitecture",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .executableTarget(
            name: "DebuggerCLI",
            dependencies: [
                "MachineRuntime",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .executableTarget(
            name: "PlaygroundCLI",
            dependencies: [
                "MachineRuntime",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),

        .target(
            name: "TestSupport",
            dependencies: [
                "MachineRuntime",
                "MachineKit",
                "MMIXArchitecture",
                "MIXArchitecture"
            ],
            path: "Tests/TestSupport"
        ),

        .testTarget(
            name: "MMIXArchitectureTests",
            dependencies: [
                "TestSupport", "MMIXArchitecture",
                .product(name: "Testing", package: "swift-testing")
            ]
        ),
        .testTarget(
            name: "MIXArchitectureTests",
            dependencies: [
                "TestSupport", "MIXArchitecture",
                .product(name: "Testing", package: "swift-testing")
            ]
        ),
        .testTarget(
            name: "MachineKitTests",
            dependencies: [
                "TestSupport", "MachineKit",
                .product(name: "Testing", package: "swift-testing")
            ]
        ),
        .testTarget(
            name: "MachineRuntimeTests",
            dependencies: [
                "TestSupport", "MachineRuntime",
                .product(name: "Testing", package: "swift-testing")
            ]
        ),
    ]
)
