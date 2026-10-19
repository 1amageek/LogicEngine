import Foundation
import Darwin
import LogicEngine
import LogicEngineRuntime
import LogicEngineCore

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
            try printCapabilities()
            return 0
        case "simulate":
            let options = try CLIOptions(arguments: Array(arguments.dropFirst()))
            var request = try JSONDecoder().decode(LogicEngineRuntime.LogicSimulationRequest.self,
                from: options.readRequest())
            if let output = options.outputPath { request.artifactDirectory = output }
            let store = FileSystemLogicArtifactStore(rootDirectory: options.rootURL, defaultOutputDirectory: options.outputURL)
            let engine: any LogicEngineRuntime.LogicSimulationExecuting = LogicEngineRuntime.NativeLogicSimulationEngine(artifactStore: store)
            let result = try await engine.execute(request)
            try printJSON(result)
            return result.assessment.status == .failed ? 2 : 0
        case "verify-simulation":
            let options = try CLIOptions(arguments: Array(arguments.dropFirst()))
            let request = try JSONDecoder().decode(LogicSimulationVerificationRequest.self, from: options.readRequest())
            let store = FileSystemLogicArtifactStore(rootDirectory: options.rootURL, defaultOutputDirectory: options.outputURL)
            let loader: any LogicSimulationArtifactLoading = NativeLogicSimulationEngine(artifactStore: store)
            let result = try await loader.load(request.acceptance, expectedRequest: request.expectedRequest, limits: request.limits)
            try printJSON(result)
            return result.assessment.status == .passed ? 0 : 2
        case "synthesize":
            let options = try CLIOptions(arguments: Array(arguments.dropFirst()))
            var request = try JSONDecoder().decode(LogicEngineRuntime.LogicSynthesisRequest.self,
                from: options.readRequest())
            if let output = options.outputPath { request.artifactDirectory = output }
            let store = FileSystemLogicArtifactStore(rootDirectory: options.rootURL, defaultOutputDirectory: options.outputURL)
            let engine: any LogicEngineRuntime.LogicSynthesisExecuting = LogicEngineRuntime.NativeLogicSynthesisEngine(artifactStore: store)
            let result = try await engine.execute(request)
            try printJSON(result)
            return 0
        case "verify-mapped":
            let options = try CLIOptions(arguments: Array(arguments.dropFirst()))
            let request = try JSONDecoder().decode(LogicEquivalenceRequest.self, from: options.readRequest())
            let store = FileSystemLogicArtifactStore(rootDirectory: options.rootURL, defaultOutputDirectory: options.outputURL)
            let engine: any LogicEquivalenceExecuting = NativeLogicEquivalenceEngine(artifactStore: store)
            try printJSON(try await engine.execute(request))
            return 0
        default:
            printUsage()
            return 2
        }
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        print(String(decoding: data, as: UTF8.self))
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
        print("Current synthesize, simulate, verify-simulation and verify-mapped commands require --maximum-request-bytes N before decoding request JSON.")
        print("Usage: logic-engine <capabilities|simulate|verify-simulation|synthesize|verify-mapped> --request PATH --maximum-request-bytes N [--root PATH] [--output PATH]")
    }

    private static func printCapabilities() throws {
        try printJSON(LogicEngineCapabilities.native)
    }

    private struct CLIOptions {
        let requestURL: URL
        let rootURL: URL
        let outputURL: URL?
        let outputPath: String?

        let maximumRequestBytes: UInt64

        func readRequest() throws -> Data {
            return try LogicArtifactFileReader.read(requestURL, maximumBytes: maximumRequestBytes)
        }

        init(arguments: [String]) throws {
            guard let rawLimit = Self.value(for: "--maximum-request-bytes", in: arguments),
                  let limit = UInt64(rawLimit), limit > 0, limit < UInt64(Int.max) else {
                throw LogicExecutionError.missingPrerequisite("--maximum-request-bytes must be a positive host-addressable byte count")
            }
            maximumRequestBytes = limit
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

}
