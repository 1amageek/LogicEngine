import LogicEngineCore
import LogicIR
import XcircuitePackage

/// Package-owned compatibility boundary for the existing native lowerer.
public struct NativeLogicLoweringFoundationEngine: LogicLoweringFoundationEngine {
    public let legacyEngine: any LogicLoweringExecuting

    public init(
        legacyEngine: any LogicLoweringExecuting = NativeLogicLoweringEngine()
    ) {
        self.legacyEngine = legacyEngine
    }

    public func execute(
        _ request: LogicLoweringFoundationRequest
    ) async throws -> LogicLoweringFoundationResult {
        try request.validate()
        let bridge = LogicFoundationArtifactBridge()
        let designArtifact = try bridge.legacyReference(
            from: request.design.artifact,
            runID: request.runID,
            kind: .rtl,
            format: .json
        )
        let legacyRequest = LogicLoweringRequest(
            runID: request.runID,
            inputs: try request.inputs.map {
                try bridge.legacyReference(from: $0, runID: request.runID)
            },
            design: LogicDesignReference(
                artifact: designArtifact,
                topDesignName: request.design.topDesignName,
                // Lowering validates the canonical RTL snapshot revision. The
                // Foundation artifact digest already protects the file bytes;
                // it is not interchangeable with the snapshot's canonical
                // design digest.
                designDigest: request.design.designRevision?.hexadecimalValue ?? ""
            ),
            artifactDirectory: request.artifactDirectory
        )
        let legacyResult = try await legacyEngine.execute(legacyRequest)
        return try LogicLoweringFoundationResult(
            legacy: legacyResult,
            request: request
        )
    }
}
