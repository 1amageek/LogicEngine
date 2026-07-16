// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "LogicEngine",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LogicEngineCore", targets: ["LogicEngineCore"]),
        .library(name: "LogicLowering", targets: ["LogicLowering"]),
        .library(name: "LogicSimulation", targets: ["LogicSimulation"]),
        .library(name: "LogicSynthesis", targets: ["LogicSynthesis"]),
        .library(name: "LogicEvidence", targets: ["LogicEvidence"]),
        .library(name: "LogicEngine", targets: ["LogicEngine"]),
        .executable(name: "logic-engine", targets: ["LogicEngineCLI"]),
    ],
    dependencies: [
        .package(path: "../CircuiteFoundation"),
        .package(path: "../LogicDesign"),
        .package(path: "../TimingEngine"),
        .package(path: "../PDKKit"),
    ],
    targets: [
        .target(
            name: "LogicEngineCore",
            dependencies: [
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "LogicIR", package: "LogicDesign"),
            ]
        ),
        .target(
            name: "LogicLowering",
            dependencies: [
                "LogicEngineCore",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "LogicIR", package: "LogicDesign"),
            ]
        ),
        .target(
            name: "LogicSimulation",
            dependencies: [
                "LogicEngineCore",
                "LogicLowering",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "LogicIR", package: "LogicDesign"),
            ]
        ),
        .target(
            name: "LogicSynthesis",
            dependencies: [
                "LogicEngineCore",
                "LogicLowering",
                "LogicSimulation",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "LogicIR", package: "LogicDesign"),
                .product(name: "PowerIntent", package: "LogicDesign"),
                .product(name: "TimingCore", package: "TimingEngine"),
                .product(name: "PDKCore", package: "PDKKit"),
            ]
        ),
        .target(
            name: "LogicEvidence",
            dependencies: [
                "LogicSimulation",
                "LogicSynthesis",
                "LogicEngineCore",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "LogicIR", package: "LogicDesign"),
            ]
        ),
        .target(
            name: "LogicEngine",
            dependencies: [
                "LogicLowering",
                "LogicSimulation",
                "LogicSynthesis",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .testTarget(
            name: "LogicEngineTests",
            dependencies: ["LogicEngineCore", "LogicLowering", "LogicSimulation", "LogicSynthesis", "LogicEvidence", "LogicEngine", .product(name: "SystemVerilogFrontend", package: "LogicDesign")],
            resources: [.copy("Fixtures")]
        ),
        .executableTarget(
            name: "LogicEngineCLI",
            dependencies: ["LogicEngineCore", "LogicLowering", "LogicSimulation", "LogicSynthesis", "LogicEvidence", "LogicEngine", .product(name: "LogicIR", package: "LogicDesign")]
        ),
    ]
)
