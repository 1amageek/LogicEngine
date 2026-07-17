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
            let result = try await NativeLogicSimulationEngine(artifactStore: store).execute(request)
            printJSON(result)
            return exitCode(for: result.status)
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
            let result = try await NativeLogicLoweringEngine(artifactStore: store).execute(request)
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
            let result = try await NativeLogicSynthesisEngine(artifactStore: store).execute(request)
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
            let result = try await NativeLogicBoundedTemporalEquivalenceEngine(artifactStore: store).execute(request)
            printJSON(result)
            return exitCode(for: result.status)
        case "unbounded-equivalence":
            let options = try CLIOptions(arguments: Array(arguments.dropFirst()))
            let requestData = try Data(contentsOf: options.requestURL)
            var request = try JSONDecoder().decode(
                LogicUnboundedTemporalEquivalenceRequest.self,
                from: requestData
            )
            if let outputPath = options.outputPath {
                request = LogicUnboundedTemporalEquivalenceRequest(
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
            let result = try await NativeLogicUnboundedTemporalEquivalenceEngine(
                artifactStore: store
            ).execute(request)
            printJSON(result)
            return exitCode(for: result.status)
        case "assess-evidence":
            let options = try EvidenceCLIOptions(arguments: Array(arguments.dropFirst()))
            let suiteData = try Data(contentsOf: options.suiteURL)
            let decodedSuite = try JSONDecoder().decode(LogicEvidenceSuite.self, from: suiteData)
            let suite = Self.suite(decodedSuite, overridingArtifactDirectory: options.outputPath)
            let store = FileSystemLogicArtifactStore(
                rootDirectory: options.rootURL,
                defaultOutputDirectory: options.outputURL
            )
            let executor = NativeLogicEvidenceExecutor(
                simulation: NativeLogicSimulationEngine(artifactStore: store),
                synthesis: NativeLogicSynthesisEngine(artifactStore: store),
                unbounded: NativeLogicUnboundedTemporalEquivalenceEngine(artifactStore: store)
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
        print("Usage: logic-engine <capabilities|lower|simulate|synthesize|bounded-equivalence|unbounded-equivalence|assess-evidence> [--request PATH|--suite PATH] [--oracle PATH] [--root PATH] [--output PATH]")
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

    private static func suite(
        _ suite: LogicEvidenceSuite,
        overridingArtifactDirectory artifactDirectory: String?
    ) -> LogicEvidenceSuite {
        guard let artifactDirectory else {
            return suite
        }

        var updatedSuite = suite
        updatedSuite.cases = suite.cases.map { evidenceCase in
            var updatedCase = evidenceCase
            let baseOutputDirectory = artifactDirectory.hasSuffix("/")
                ? String(artifactDirectory.dropLast())
                : artifactDirectory
            let runOutputDirectory = "\(baseOutputDirectory)/\(Self.evidenceRunID(for: evidenceCase.request.runID))"
            switch evidenceCase.request {
            case .simulation(var request):
                request.artifactDirectory = runOutputDirectory
                updatedCase.request = .simulation(request)
            case .synthesis(var request):
                request.artifactDirectory = runOutputDirectory
                updatedCase.request = .synthesis(request)
            case .unbounded(let request):
                updatedCase.request = .unbounded(LogicUnboundedTemporalEquivalenceRequest(
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
                    artifactDirectory: runOutputDirectory
                ))
            }
            return updatedCase
        }
        return updatedSuite
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
