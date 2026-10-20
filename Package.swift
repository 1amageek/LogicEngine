// swift-tools-version: 6.4
import PackageDescription

let circuiteFoundationDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/CircuiteFoundation.git",
    revision: "5f132c58209123433e0e479e1ea61096e46061ba"
)

let logicDesignDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/LogicDesign.git",
    revision: "5e1d3eec838a0add91c617413682d186a5182335"
)

let timingEngineDependency: Package.Dependency = .package(url: "https://github.com/1amageek/TimingEngine.git",
    revision: "d6d0bec0ee5b97a25687ad0db02e127b6d3a9df0"
)

let pdkKitDependency: Package.Dependency = .package(url: "https://github.com/1amageek/PDKKit.git",
    revision: "d27217e8312c072f4fde731d722e48f3040d5a5b"
)

let package = Package(
    name: "LogicEngine",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "LogicSynthesis", targets: ["LogicSynthesis"]),
        .library(name: "LogicEngineCore", targets: ["LogicEngineCore"]),
        .library(name: "LogicEngineRuntime", targets: ["LogicEngineRuntime"]),
        .library(name: "LogicLowering", targets: ["LogicLowering"]),
        .library(name: "LogicProof", targets: ["LogicProof"]),
        .library(name: "LogicSimulation", targets: ["LogicSimulation"]),
        .library(name: "LogicEvidence", targets: ["LogicEvidence"]),
        .library(name: "LogicEngine", targets: ["LogicEngine"]),
        .executable(name: "logic-engine", targets: ["LogicEngineCLI"]),
    ],
    dependencies: [
        circuiteFoundationDependency,
        logicDesignDependency,
        timingEngineDependency,
        pdkKitDependency,
    ],
    targets: [
        .target(name: "LogicOptimizationProbeSupport", dependencies: ["LogicSynthesis", "LogicProof", "LogicSimulation", "LogicProofProbeSupport", "LogicLowering", "LogicWordLoweringProbeSupport",
            .product(name: "SystemVerilogFrontend", package: "LogicDesign"),
            .product(name: "LogicIR", package: "LogicDesign"),
            .product(name: "LogicKernelCore", package: "LogicDesign"),
            .product(name: "CircuiteFoundation", package: "CircuiteFoundation")], exclude: ["DESIGN.md"]),
        .testTarget(name: "LogicOptimizationTests", dependencies: ["LogicOptimizationProbeSupport", "LogicSynthesis", "LogicProof", "LogicProofProbeSupport", "LogicSimulation",
            .product(name: "LogicIR", package: "LogicDesign"), .product(name: "LogicKernelCore", package: "LogicDesign")]),
        .executableTarget(name: "LogicOptimizationPortabilityProbe", dependencies: ["LogicOptimizationProbeSupport"]),
        .executableTarget(name: "LogicOptimizationEmbeddedPortabilityProbe", dependencies: ["LogicOptimizationProbeSupport"],
            linkerSettings: [.linkedLibrary("swiftUnicodeDataTables", .when(platforms: [.wasi])),
                .unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=4194304"], .when(platforms: [.wasi]))]),

        .target(name: "LogicSynthesis", dependencies: [
            .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            .product(name: "LogicIR", package: "LogicDesign"),
            .product(name: "LogicKernelCore", package: "LogicDesign")
        ], exclude: ["DESIGN.md", "StateOptimization/DESIGN.md", "TechnologyMapping/DESIGN.md"]),
        .target(name: "LogicEngineRuntime", dependencies: [
            .product(name: "PDKCore", package: "PDKKit"),
            "LogicEngineCore", "LogicLowering", "LogicSimulation", "LogicProof", "LogicSynthesis",
            .product(name: "LogicDesignSerialization", package: "LogicDesign"),
            .product(name: "SystemVerilogFrontend", package: "LogicDesign"),
            .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
            .product(name: "STAEngine", package: "TimingEngine"),
            .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
            .product(name: "LogicIR", package: "LogicDesign"),
            .product(name: "LogicKernelCore", package: "LogicDesign"),
            .product(name: "TimingCore", package: "TimingEngine")
        ], exclude: ["DESIGN.md", "TechnologyLibraryCompilation/DESIGN.md", "ActualCellExecution/DESIGN.md", "VerifiedArtifacts/DESIGN.md", "EventExecution/DESIGN.md"]),
        .testTarget(name: "LogicRuntimeTests", dependencies: ["LogicEngineRuntime", "LogicEngineCore", "LogicProof", "LogicSynthesis", "LogicSimulation",
            .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
            .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
            .product(name: "LogicIR", package: "LogicDesign"),
            .product(name: "LogicKernelCore", package: "LogicDesign"),
            .product(name: "STAEngine", package: "TimingEngine"),
            .product(name: "TimingCore", package: "TimingEngine"),
            .product(name: "PDKCore", package: "PDKKit")], resources: [.copy("Fixtures")]),
        .testTarget(name: "LogicLibraryCompilationTests", dependencies: ["LogicEngineRuntime", "LogicSimulation", "LogicSynthesis", "LogicProof", "LogicProofProbeSupport",
            .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
            .product(name: "LogicIR", package: "LogicDesign"),
            .product(name: "LogicKernelCore", package: "LogicDesign"),
            .product(name: "TimingCore", package: "TimingEngine")]),
        .target(
            name: "LogicWordLoweringProbeSupport",
            dependencies: ["LogicLowering", .product(name: "SystemVerilogFrontend", package: "LogicDesign"), .product(name: "LogicIR", package: "LogicDesign"),
                .product(name: "LogicKernelCore", package: "LogicDesign"),
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation")],
            exclude: ["DESIGN.md"]
        ),
        .executableTarget(name: "LogicWordLoweringPortabilityProbe", dependencies: ["LogicWordLoweringProbeSupport"], exclude: ["DESIGN.md"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=4194304"], .when(platforms: [.wasi]))]),
        .executableTarget(
            name: "LogicWordLoweringEmbeddedPortabilityProbe", dependencies: ["LogicWordLoweringProbeSupport"],
            exclude: ["DESIGN.md"],
            linkerSettings: [.linkedLibrary("swiftUnicodeDataTables", .when(platforms: [.wasi])),
                .unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=4194304"], .when(platforms: [.wasi]))]
        ),
        .target(
            name: "LogicBitLoweringProbeSupport",
            dependencies: ["LogicLowering", .product(name: "LogicIR", package: "LogicDesign"),
                .product(name: "LogicKernelCore", package: "LogicDesign"),
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation")],
            exclude: ["DESIGN.md"]
        ),
        .executableTarget(name: "LogicBitLoweringPortabilityProbe", dependencies: ["LogicBitLoweringProbeSupport"]),
        .executableTarget(
            name: "LogicBitLoweringEmbeddedPortabilityProbe", dependencies: ["LogicBitLoweringProbeSupport"],
            linkerSettings: [.linkedLibrary("swiftUnicodeDataTables", .when(platforms: [.wasi]))]
        ),
        .target(
            name: "LogicEngineCore",
            dependencies: [
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
            ], exclude: ["DESIGN.md", "ArtifactStorage/DESIGN.md"]
        ),
        .target(
            name: "LogicLowering",
            dependencies: [
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "LogicKernelCore", package: "LogicDesign"),
                .product(name: "LogicIR", package: "LogicDesign"),
            ],
            exclude: ["DESIGN.md", "BitExpansion/DESIGN.md", "ProceduralLowering/DESIGN.md"]
        ),
        .target(name: "LogicProof", dependencies: ["LogicSimulation",
            .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            .product(name: "LogicIR", package: "LogicDesign"),
            .product(name: "LogicKernelCore", package: "LogicDesign")
        ], exclude: ["DESIGN.md", "CNFModel/DESIGN.md", "RUPChecking/DESIGN.md", "CDCLSearch/DESIGN.md", "CircuitEquivalence/DESIGN.md"]),
        .testTarget(name: "LogicProofTests", dependencies: ["LogicProof", "LogicSimulation", "LogicProofProbeSupport", .product(name: "LogicIR", package: "LogicDesign"),
            .product(name: "LogicKernelCore", package: "LogicDesign")]),
        .target(name: "LogicProofProbeSupport", dependencies: ["LogicProof", "LogicSimulation", .product(name: "LogicIR", package: "LogicDesign"),
            .product(name: "CircuiteFoundation", package: "CircuiteFoundation"), .product(name: "LogicKernelCore", package: "LogicDesign")], exclude: ["DESIGN.md"]),
        .executableTarget(name: "LogicProofPortabilityProbe", dependencies: ["LogicProofProbeSupport"], exclude: ["DESIGN.md"]),
        .executableTarget(name: "LogicProofEmbeddedPortabilityProbe", dependencies: ["LogicProofProbeSupport"], exclude: ["DESIGN.md"],
            linkerSettings: [.linkedLibrary("swiftUnicodeDataTables", .when(platforms: [.wasi]))]),
        .target(name: "LogicSimulationProbeSupport", dependencies: ["LogicSimulation",
            .product(name: "SystemVerilogFrontend", package: "LogicDesign"),
            .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            .product(name: "LogicIR", package: "LogicDesign"), .product(name: "LogicKernelCore", package: "LogicDesign")], exclude: ["DESIGN.md"]),
        .testTarget(name: "LogicSimulationKernelTests", dependencies: ["LogicSimulation", "LogicSimulationProbeSupport",
            .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
            .product(name: "LogicIR", package: "LogicDesign"), .product(name: "LogicKernelCore", package: "LogicDesign")]),
        .executableTarget(name: "LogicSimulationPortabilityProbe", dependencies: ["LogicSimulationProbeSupport"], exclude: ["DESIGN.md"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=4194304"], .when(platforms: [.wasi]))]),
        .executableTarget(name: "LogicSimulationEmbeddedPortabilityProbe", dependencies: ["LogicSimulationProbeSupport"], exclude: ["DESIGN.md"],
            linkerSettings: [.linkedLibrary("swiftUnicodeDataTables", .when(platforms: [.wasi])),
                .unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=4194304"], .when(platforms: [.wasi]))]),
        .target(name: "LogicSimulation", dependencies: [
            .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            .product(name: "LogicIR", package: "LogicDesign"),
            .product(name: "LogicKernelCore", package: "LogicDesign")
        ], exclude: ["DESIGN.md", "CellEvents/DESIGN.md", "RTLEvents/DESIGN.md", "BinaryRelations/DESIGN.md"]),
        .target(
            name: "LogicEvidence",
            dependencies: [
                .product(name: "LogicIR", package: "LogicDesign"),
                .product(name: "LogicDesignSerialization", package: "LogicDesign"),
            ],
            exclude: ["DESIGN.md"]
        ),
        .target(
            name: "LogicEngine",
            dependencies: [
                "LogicEngineCore", "LogicEngineRuntime", "LogicLowering", "LogicSimulation", "LogicSynthesis", "LogicProof",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ], exclude: ["DESIGN.md"]
        ),
        .testTarget(
            name: "LogicWordLoweringTests",
            dependencies: ["LogicLowering", .product(name: "SystemVerilogFrontend", package: "LogicDesign"), .product(name: "LogicIR", package: "LogicDesign"),
                .product(name: "LogicKernelCore", package: "LogicDesign"),
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "LogicDesignSerialization", package: "LogicDesign"), "LogicWordLoweringProbeSupport"]
        ),
        .testTarget(
            name: "LogicBitLoweringTests",
            dependencies: ["LogicLowering", .product(name: "LogicIR", package: "LogicDesign"),
                .product(name: "LogicKernelCore", package: "LogicDesign"),
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation")]
        ),
        .testTarget(
            name: "LogicEngineTests",
            dependencies: [
                "LogicEngineCore",
                "LogicEvidence",
                "LogicEngine",
                "LogicEngineRuntime",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
            ],
            resources: [.copy("Fixtures")]
        ),
        .executableTarget(
            name: "LogicEngineCLI",
            dependencies: [
                "LogicEngineRuntime",
                "LogicEngineCore",
                "LogicEngine",
            ], exclude: ["DESIGN.md"]
        ),
    ]
)
