import LogicEngineCore
import LogicIR
import XcircuitePackage

/// Package-owned compatibility boundary for the existing native simulator.
public struct NativeLogicSimulationFoundationEngine: LogicSimulationFoundationEngine {
    public let legacyEngine: any LogicSimulationExecuting

    public init(
        legacyEngine: any LogicSimulationExecuting = NativeLogicSimulationEngine()
    ) {
        self.legacyEngine = legacyEngine
    }

    public func execute(
        _ request: LogicSimulationFoundationRequest
    ) async throws -> LogicSimulationFoundationResult {
        try request.validate()
        let legacyRequest = try makeLegacyRequest(request)
        let legacyResult = try await legacyEngine.execute(legacyRequest)
        return try LogicSimulationFoundationResult(
            legacy: legacyResult,
            request: request
        )
    }

    private func makeLegacyRequest(
        _ request: LogicSimulationFoundationRequest
    ) throws -> LogicSimulationRequest {
        let bridge = LogicFoundationArtifactBridge()
        let designArtifact = try bridge.legacyReference(
            from: request.design.artifact,
            runID: request.runID,
            kind: .rtl,
            format: .json
        )
        let legacyInputs = try request.inputs.map {
            try bridge.legacyReference(from: $0, runID: request.runID)
        }
        let stimulus = try request.stimulus.map {
            try bridge.legacyReference(
                from: $0,
                runID: request.runID,
                kind: .testPattern,
                format: .json
            )
        }
        return LogicSimulationRequest(
            runID: request.runID,
            inputs: legacyInputs,
            design: LogicDesignReference(
                artifact: designArtifact,
                topDesignName: request.design.topDesignName,
                designDigest: request.design.designRevision?.hexadecimalValue
                    ?? request.design.artifact.digest.hexadecimalValue
            ),
            stimulus: stimulus,
            seed: request.seed,
            waveformFormat: request.waveformFormat,
            artifactDirectory: request.artifactDirectory
        )
    }
}
