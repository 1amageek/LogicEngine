// swift-tools-version: 6.3
import PackageDescription
import Foundation

let workspaceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let isLSIWorkspace = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("docs/workspace-packages.json").path
)

let circuiteFoundationDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("CircuiteFoundation/Package.swift").path
)
    ? .package(path: "../CircuiteFoundation")
    : .package(url: "https://github.com/1amageek/CircuiteFoundation.git", revision: "dc792c88e189c822c9f83ea86cf139ee68560dca")

let logicDesignDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("LogicDesign/Package.swift").path
)
    ? .package(path: "../LogicDesign")
    : .package(url: "https://github.com/1amageek/LogicDesign.git", revision: "e8f8e1dace0445ddd816929c4ca0fe17cca12a7b")

let timingEngineDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("TimingEngine/Package.swift").path
)
    ? .package(path: "../TimingEngine")
    : .package(url: "https://github.com/1amageek/TimingEngine.git", revision: "7809651994017a932314b747b948ac14e32e779b")

let pdkKitDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("PDKKit/Package.swift").path
)
    ? .package(path: "../PDKKit")
    : .package(url: "https://github.com/1amageek/PDKKit.git", revision: "3ab7e3b6094d2de672b582d90076cf58b6527766")

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
                "LogicEngineCore",
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
