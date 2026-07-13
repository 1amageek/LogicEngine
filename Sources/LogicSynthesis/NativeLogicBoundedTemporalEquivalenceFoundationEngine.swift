import Foundation
import LogicEngineCore
import LogicIR
import LogicSimulation
import XcircuitePackage

/// Package-owned compatibility boundary for the native bounded proof engine.
public struct NativeLogicBoundedTemporalEquivalenceFoundationEngine:
    LogicBoundedTemporalEquivalenceFoundationEngine
{
    public let legacyEngine: any LogicBoundedTemporalEquivalenceExecuting

    public init(
        legacyEngine: any LogicBoundedTemporalEquivalenceExecuting = NativeLogicBoundedTemporalEquivalenceEngine()
    ) {
        self.legacyEngine = legacyEngine
    }

    public func execute(
        _ request: LogicBoundedTemporalEquivalenceFoundationRequest
    ) async throws -> LogicBoundedTemporalEquivalenceFoundationResult {
        try request.validate()
        let bridge = LogicFoundationArtifactBridge()
        let referenceArtifact = try bridge.legacyReference(
            from: request.referenceDesign.artifact,
            runID: request.runID,
            kind: .netlist,
            format: .json
        )
        let implementationArtifact = try bridge.legacyReference(
            from: request.implementationDesign.artifact,
            runID: request.runID,
            kind: .netlist,
            format: .json
        )
        let stimulus = try bridge.legacyReference(
            from: request.stimulus,
            runID: request.runID,
            kind: .testPattern,
            format: .json
        )
        let legacyRequest = LogicBoundedTemporalEquivalenceRequest(
            runID: request.runID,
            inputs: try request.inputs.map {
                try bridge.legacyReference(from: $0, runID: request.runID)
            },
            referenceDesign: LogicDesignReference(
                artifact: referenceArtifact,
                topDesignName: request.referenceDesign.topDesignName,
                designDigest: request.referenceDesign.designRevision?.hexadecimalValue
                    ?? request.referenceDesign.artifact.digest.hexadecimalValue
            ),
            implementationDesign: LogicDesignReference(
                artifact: implementationArtifact,
                topDesignName: request.implementationDesign.topDesignName,
                designDigest: request.implementationDesign.designRevision?.hexadecimalValue
                    ?? request.implementationDesign.artifact.digest.hexadecimalValue
            ),
            stimulus: stimulus,
            outputSignals: request.outputSignals,
            sampleLimit: request.sampleLimit,
            artifactDirectory: request.artifactDirectory
        )
        let legacyResult = try await legacyEngine.execute(legacyRequest)
        return try LogicBoundedTemporalEquivalenceFoundationResult(
            legacy: legacyResult,
            request: request
        )
    }
}
