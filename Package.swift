// swift-tools-version: 6.3
import PackageDescription

let circuiteFoundationDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/CircuiteFoundation.git",
    revision: "ae88104c556f5802819713ed741f5b2fffffc2d9"
)

let logicDesignDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/LogicDesign.git",
    revision: "d13cebf1454e124a352f87186a22a70ef47d99a5"
)

let timingEngineDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/TimingEngine.git",
    revision: "2c0e6df5ac88a2e331fbb41403e4d8265db64314"
)

let pdkKitDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/PDKKit.git",
    revision: "14f7b508dd8961ed4bfa6d6e29600fdc5c6ae9f5"
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
