// swift-tools-version: 6.3
import PackageDescription

let circuiteFoundationDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/CircuiteFoundation.git",
    exact: "26.812.0"
)

let logicDesignDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/LogicDesign.git",
    exact: "26.812.0"
)

let timingEngineDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/TimingEngine.git",
    exact: "26.812.0"
)

let pdkKitDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/PDKKit.git",
    exact: "26.812.0"
)

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
        circuiteFoundationDependency,
        logicDesignDependency,
        timingEngineDependency,
        pdkKitDependency,
    ],
    targets: [
        .target(
            name: "LogicEngineCore",
            dependencies: [
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationFileSystem", package: "CircuiteFoundation"),
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
                .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
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
                "LogicEngineCore",
                "LogicLowering",
                "LogicSimulation",
                "LogicSynthesis",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .testTarget(
            name: "LogicEngineTests",
            dependencies: [
                "LogicEngineCore",
                "LogicLowering",
                "LogicSimulation",
                "LogicSynthesis",
                "LogicEvidence",
                "LogicEngine",
                .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
                .product(name: "SystemVerilogFrontend", package: "LogicDesign"),
                .product(name: "TimingCore", package: "TimingEngine"),
                .product(name: "PDKCore", package: "PDKKit"),
            ],
            resources: [.copy("Fixtures")]
        ),
        .executableTarget(
            name: "LogicEngineCLI",
            dependencies: ["LogicEngineCore", "LogicLowering", "LogicSimulation", "LogicSynthesis", "LogicEvidence", "LogicEngine", .product(name: "LogicIR", package: "LogicDesign")]
        ),
    ]
)
