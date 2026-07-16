import Foundation
import Darwin
import CircuiteFoundation
import LogicEngine
import LogicEngineCore
import LogicLowering
import LogicEvidence
import LogicSimulation
import LogicSynthesis
import LogicIR

@main
struct LogicEngineCLI {
    static func main() async {
        do {
            let code = try await run(arguments: Array(CommandLine.arguments.dropFirst()))
            exit(code)
        } catch {
            printFailure(error)
            exit(2)
        }
    }

    private static func run(arguments: [String]) async throws -> Int32 {
        guard let command = arguments.first else {
            printUsage()
            return 2
        }
        switch command {
        case "capabilities":
            printCapabilities()
            return 0
        case "simulate":
            let options = try CLIOptions(arguments: Array(arguments.dropFirst()))
            let requestData = try Data(contentsOf: options.requestURL)
            var request = try JSONDecoder().decode(LogicSimulationRequest.self, from: requestData)
            if let outputPath = options.outputPath {
                request.artifactDirectory = outputPath
            }
            let store = FileSystemLogicArtifactStore(
                rootDirectory: options.rootURL,
                defaultOutputDirectory: options.outputURL
            )
            let envelope = try await NativeLogicSimulationEngine(artifactStore: store).execute(request)
            printJSON(envelope)
            return exitCode(for: envelope.status)
        case "lower":
            let options = try CLIOptions(arguments: Array(arguments.dropFirst()))
            let requestData = try Data(contentsOf: options.requestURL)
            var request = try JSONDecoder().decode(LogicLoweringRequest.self, from: requestData)
            if let outputPath = options.outputPath {
                request.artifactDirectory = outputPath
            }
            let store = FileSystemLogicArtifactStore(
                rootDirectory: options.rootURL,
                defaultOutputDirectory: options.outputURL
            )
            let envelope = try await NativeLogicLoweringEngine(artifactStore: store).execute(request)
            printJSON(envelope)
            return exitCode(for: envelope.status)
        case "foundation-lower":
            let options = try CLIOptions(arguments: Array(arguments.dropFirst()))
            let requestData = try Data(contentsOf: options.requestURL)
            var request = try JSONDecoder().decode(LogicLoweringFoundationRequest.self, from: requestData)
            if let outputPath = options.outputPath {
                request = LogicLoweringFoundationRequest(
                    runID: request.runID,
                    design: request.design,
                    inputs: request.inputs,
                    artifactDirectory: outputPath
                )
            }
            let store = FileSystemLogicArtifactStore(
                rootDirectory: options.rootURL,
                defaultOutputDirectory: options.outputURL
            )
            let engine = NativeLogicLoweringFoundationEngine(
                engine: NativeLogicLoweringEngine(artifactStore: store)
            )
            let result = try await engine.execute(request)
            printJSON(result)
            return exitCode(for: result.status)
        case "synthesize":
            let options = try CLIOptions(arguments: Array(arguments.dropFirst()))
            let requestData = try Data(contentsOf: options.requestURL)
            var request = try JSONDecoder().decode(LogicSynthesisRequest.self, from: requestData)
            if let outputPath = options.outputPath {
                request.artifactDirectory = outputPath
            }
            let store = FileSystemLogicArtifactStore(
                rootDirectory: options.rootURL,
                defaultOutputDirectory: options.outputURL
            )
            let envelope = try await NativeLogicSynthesisEngine(artifactStore: store).execute(request)
            printJSON(envelope)
            return exitCode(for: envelope.status)
        case "foundation-simulate":
            let options = try CLIOptions(arguments: Array(arguments.dropFirst()))
            let requestData = try Data(contentsOf: options.requestURL)
            var request = try JSONDecoder().decode(LogicSimulationFoundationRequest.self, from: requestData)
            if let outputPath = options.outputPath {
                request = LogicSimulationFoundationRequest(
                    runID: request.runID,
                    design: request.design,
                    inputs: request.inputs,
                    stimulus: request.stimulus,
                    seed: request.seed,
                    waveformFormat: request.waveformFormat,
                    artifactDirectory: outputPath
                )
            }
            let store = FileSystemLogicArtifactStore(
                rootDirectory: options.rootURL,
                defaultOutputDirectory: options.outputURL
            )
            let engine = NativeLogicSimulationFoundationEngine(
                engine: NativeLogicSimulationEngine(artifactStore: store)
            )
            let result = try await engine.execute(request)
            printJSON(result)
            return exitCode(for: result.status)
        case "foundation-synthesize":
            let options = try CLIOptions(arguments: Array(arguments.dropFirst()))
            let requestData = try Data(contentsOf: options.requestURL)
            var request = try JSONDecoder().decode(LogicSynthesisFoundationRequest.self, from: requestData)
            if let outputPath = options.outputPath {
                request = LogicSynthesisFoundationRequest(
                    runID: request.runID,
                    design: request.design,
                    libraries: request.libraries,
                    constraints: request.constraints,
                    pdkManifest: request.pdkManifest,
                    processID: request.processID,
                    pdkVersion: request.pdkVersion,
                    pdkDigest: request.pdkDigest,
                    constraintModeIDs: request.constraintModeIDs,
                    powerIntent: request.powerIntent,
                    powerIntentDesignRevision: request.powerIntentDesignRevision,
                    inputs: request.inputs,
                    artifactDirectory: outputPath
                )
            }
            let store = FileSystemLogicArtifactStore(
                rootDirectory: options.rootURL,
                defaultOutputDirectory: options.outputURL
            )
            let engine = NativeLogicSynthesisFoundationEngine(
                engine: NativeLogicSynthesisEngine(artifactStore: store)
            )
            let result = try await engine.execute(request)
            printJSON(result)
            return exitCode(for: result.status)
        case "bounded-equivalence":
            let options = try CLIOptions(arguments: Array(arguments.dropFirst()))
            let requestData = try Data(contentsOf: options.requestURL)
            var request = try JSONDecoder().decode(LogicBoundedTemporalEquivalenceRequest.self, from: requestData)
            if let outputPath = options.outputPath {
                request.artifactDirectory = outputPath
            }
            let store = FileSystemLogicArtifactStore(
                rootDirectory: options.rootURL,
                defaultOutputDirectory: options.outputURL
            )
            let envelope = try await NativeLogicBoundedTemporalEquivalenceEngine(artifactStore: store).execute(request)
            printJSON(envelope)
            return exitCode(for: envelope.status)
        case "foundation-bounded-equivalence":
            let options = try CLIOptions(arguments: Array(arguments.dropFirst()))
            let requestData = try Data(contentsOf: options.requestURL)
            var request = try JSONDecoder().decode(
                LogicBoundedTemporalEquivalenceFoundationRequest.self,
                from: requestData
            )
            if let outputPath = options.outputPath {
                request = LogicBoundedTemporalEquivalenceFoundationRequest(
                    runID: request.runID,
                    referenceDesign: request.referenceDesign,
                    implementationDesign: request.implementationDesign,
                    stimulus: request.stimulus,
                    outputSignals: request.outputSignals,
                    sampleLimit: request.sampleLimit,
                    inputs: request.inputs,
                    artifactDirectory: outputPath
                )
            }
            let store = FileSystemLogicArtifactStore(
                rootDirectory: options.rootURL,
                defaultOutputDirectory: options.outputURL
            )
            let engine = NativeLogicBoundedTemporalEquivalenceFoundationEngine(
                engine: NativeLogicBoundedTemporalEquivalenceEngine(artifactStore: store)
            )
            let result = try await engine.execute(request)
            printJSON(result)
            return exitCode(for: result.status)
        case "foundation-unbounded-equivalence":
            let options = try CLIOptions(arguments: Array(arguments.dropFirst()))
            let requestData = try Data(contentsOf: options.requestURL)
            var request = try JSONDecoder().decode(
                LogicUnboundedTemporalEquivalenceFoundationRequest.self,
                from: requestData
            )
            if let outputPath = options.outputPath {
                request = LogicUnboundedTemporalEquivalenceFoundationRequest(
                    runID: request.runID,
                    referenceDesign: request.referenceDesign,
                    implementationDesign: request.implementationDesign,
                    outputSignals: request.outputSignals,
                    valueDomain: request.valueDomain,
                    stateSpaceLimit: request.stateSpaceLimit,
                    transitionLimit: request.transitionLimit,
                    timeoutNanoseconds: request.timeoutNanoseconds,
                    clockSignal: request.clockSignal,
                    inputs: request.inputs,
                    artifactDirectory: outputPath
                )
            }
            let store = FileSystemLogicArtifactStore(
                rootDirectory: options.rootURL,
                defaultOutputDirectory: options.outputURL
            )
            let result = try await NativeLogicUnboundedTemporalEquivalenceFoundationEngine(
                artifactStore: store
            ).execute(request)
            printJSON(result)
            return exitCode(for: result.status)
        case "assess-evidence":
            let options = try EvidenceCLIOptions(arguments: Array(arguments.dropFirst()))
            let suiteData = try Data(contentsOf: options.suiteURL)
            let suite = try JSONDecoder().decode(LogicEvidenceSuite.self, from: suiteData)
            let store = FileSystemLogicArtifactStore(
                rootDirectory: options.rootURL,
                defaultOutputDirectory: options.outputURL
            )
            let executor = NativeLogicEvidenceExecutor(
                simulation: NativeLogicSimulationEngine(artifactStore: store),
                synthesis: NativeLogicSynthesisEngine(artifactStore: store),
                unbounded: NativeLogicUnboundedTemporalEquivalenceFoundationEngine(artifactStore: store)
            )
            var report = try await NativeLogicEvidenceRunner(executor: executor).evaluate(suite)
            if let oracleURL = options.oracleURL {
                let oracleData = try Data(contentsOf: oracleURL)
                let oracle = try JSONDecoder().decode(
                    LogicEvidenceOracleObservationSet.self,
                    from: oracleData
                )
                let correlation = try NativeLogicEvidenceOracleCorrelator().correlate(
                    nativeReport: report,
                    oracle: oracle
                )
                report = report.includingOracleCorrelation(correlation)
            }
            try report.validate()
            let reportData: Data
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                reportData = try encoder.encode(report)
            } catch {
                throw LogicExecutionError.artifactWriteFailed(
                    "logic evidence report encoding failed: \(error.localizedDescription)"
                )
            }
            _ = try store.write(
                reportData,
                fileName: "logic-evidence-report.json",
                outputDirectory: options.outputPath,
                runID: Self.evidenceRunID(for: suite.suiteID),
                artifactID: "logic-evidence-report",
                kind: .report,
                format: .json
            )
            printJSON(report)
            if !report.corpusPassed {
                return 1
            }
            if options.oracleURL != nil && !report.oraclePassed {
                return 1
            }
            return 0
        default:
            printUsage()
            return 2
        }
    }

    private static func exitCode(for status: LogicExecutionStatus) -> Int32 {
        status == .completed ? 0 : 1
    }

    private static func printJSON<T: Encodable>(_ value: T) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(value)
            print(String(decoding: data, as: UTF8.self))
        } catch {
            printFailure(error)
        }
    }

    private static func printFailure(_ error: Error) {
        do {
            let data = try JSONSerialization.data(
                withJSONObject: [
                    "status": "failed",
                    "diagnostic": [
                        "code": "LOGIC_CLI_ERROR",
                        "message": error.localizedDescription,
                    ],
                ],
                options: [.sortedKeys, .prettyPrinted]
            )
            print(String(decoding: data, as: UTF8.self))
        } catch {
            print("{\"status\":\"failed\",\"diagnostic\":{\"code\":\"LOGIC_CLI_ERROR\",\"message\":\"unknown error\"}}")
        }
    }

    private static func printUsage() {
        print("Usage: logic-engine <capabilities|lower|simulate|synthesize|bounded-equivalence|foundation-lower|foundation-simulate|foundation-synthesize|foundation-bounded-equivalence|foundation-unbounded-equivalence|assess-evidence> [--request PATH|--suite PATH] [--oracle PATH] [--root PATH] [--output PATH]")
    }

    private static func evidenceRunID(for suiteID: String) -> String {
        let safeSuiteID = String(suiteID.map { character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" || character == "." {
                return character
            }
            return "_"
        })
        return "evidence-\(safeSuiteID)"
    }

    private static func printCapabilities() {
        do {
            let data = try JSONSerialization.data(
                withJSONObject: [
                    "contractVersion": LogicEngineAPI.contractVersion,
                    "products": [
                        "lowering": [
                            "implementation": "native-rtl-to-execution-graph",
                            "negativeIntegerLiterals": true,
                            "scalarLogicalOperators": true,
                            "vectorLogicalOperators": true,
                            "logicalNot": true,
                            "signedArithmetic": true,
                            "comparisons": true,
                            "division": true,
                            "modulo": true,
                            "levelSensitiveLatch": true,
                            "negativeEdgeSequential": true,
                        ],
                        "simulation": [
                            "implementation": "native-four-state",
                            "waveformFormats": ["VCD"],
                            "scalarLogicalOperators": true,
                            "vectorLogicalOperators": true,
                            "logicalNot": true,
                            "signedArithmetic": true,
                            "arithmeticRightShift": true,
                            "comparisons": true,
                            "division": true,
                            "modulo": true,
                            "levelSensitiveLatch": true,
                            "negativeEdgeSequential": true,
                            "maximumArithmeticWidthBits": 64,
                        ],
                        "synthesis": [
                            "implementation": "native-lowering-optimization-mapping",
                            "equivalenceRequired": true,
                            "acceptanceState": "pendingEquivalence",
                            "equivalenceRequestArtifact": true,
                        ],
                        "equivalence": [
                            "implementation": "native-bounded-trace",
                            "boundedTemporalTrace": true,
                            "unboundedTemporalFormal": true,
                            "unboundedImplementation": "native-exhaustive-finite-state",
                            "unboundedProofCertificate": true,
                            "waveformFormats": ["VCD"],
                        ],
                    ],
                    "evidence": [
                        "retained-corpus",
                        "independent-oracle-correlation",
                    ],
                ],
                options: [.sortedKeys, .prettyPrinted]
            )
            print(String(decoding: data, as: UTF8.self))
        } catch {
            printFailure(error)
        }
    }

    private struct CLIOptions {
        let requestURL: URL
        let rootURL: URL
        let outputURL: URL?
        let outputPath: String?

        init(arguments: [String]) throws {
            guard let requestPath = Self.value(for: "--request", in: arguments) else {
                throw LogicExecutionError.missingPrerequisite("--request is required")
            }
            let rootPath = Self.value(for: "--root", in: arguments) ?? FileManager.default.currentDirectoryPath
            let outputPath = Self.value(for: "--output", in: arguments)
            requestURL = URL(fileURLWithPath: requestPath, relativeTo: URL(fileURLWithPath: rootPath))
                .standardizedFileURL
            rootURL = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
            self.outputPath = outputPath
            if let outputPath {
                outputURL = URL(fileURLWithPath: outputPath, relativeTo: rootURL).standardizedFileURL
            } else {
                outputURL = nil
            }
        }

        private static func value(for flag: String, in arguments: [String]) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
    }

    private struct EvidenceCLIOptions {
        let suiteURL: URL
        let oracleURL: URL?
        let rootURL: URL
        let outputURL: URL?
        let outputPath: String?

        init(arguments: [String]) throws {
            guard let suitePath = Self.value(for: "--suite", in: arguments) else {
                throw LogicEvidenceError.invalidSuite("--suite is required for assess-evidence")
            }
            let rootPath = Self.value(for: "--root", in: arguments)
                ?? FileManager.default.currentDirectoryPath
            let outputPath = Self.value(for: "--output", in: arguments)
            let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
            suiteURL = URL(fileURLWithPath: suitePath, relativeTo: rootURL).standardizedFileURL
            oracleURL = Self.value(for: "--oracle", in: arguments).map {
                URL(fileURLWithPath: $0, relativeTo: rootURL).standardizedFileURL
            }
            outputURL = outputPath.map {
                URL(fileURLWithPath: $0, relativeTo: rootURL).standardizedFileURL
            }
            self.outputPath = outputPath
            self.rootURL = rootURL
        }

        private static func value(for flag: String, in arguments: [String]) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
                return nil
            }
            return arguments[index + 1]
        }
    }
}
