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
    : .package(url: "https://github.com/1amageek/CircuiteFoundation.git", revision: "2ec6ee13a89ac6885be3c26b41a9ee0ef89948ac")

let logicDesignDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("LogicDesign/Package.swift").path
)
    ? .package(path: "../LogicDesign")
    : .package(url: "https://github.com/1amageek/LogicDesign.git", revision: "09768ed203d97d1d0f79f786f9988fcb2cd39155")

let timingEngineDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("TimingEngine/Package.swift").path
)
    ? .package(path: "../TimingEngine")
    : .package(url: "https://github.com/1amageek/TimingEngine.git", revision: "81898ed51ab05c62712ebca5b1b03869b89f7682")

let pdkKitDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("PDKKit/Package.swift").path
)
    ? .package(path: "../PDKKit")
    : .package(url: "https://github.com/1amageek/PDKKit.git", revision: "28f3b83304ad2bbb0c2e0269d26616081d90d992")

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
