import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR

public struct NativeLogicLoweringFoundationEngine: LogicLoweringFoundationEngine {
    public let engine: any LogicLoweringExecuting

    public init(
        engine: any LogicLoweringExecuting = NativeLogicLoweringEngine()
    ) {
        self.engine = engine
    }

    public func execute(
        _ request: LogicLoweringFoundationRequest
    ) async throws -> LogicLoweringFoundationResult {
        try request.validate()
        let legacyRequest = LogicLoweringRequest(
            runID: request.runID,
            inputs: request.inputs,
            design: request.design,
            artifactDirectory: request.artifactDirectory
        )
        let startedAt = Date()
        let result = try await engine.execute(legacyRequest)
        let completedAt = Date()
        let sourceDigest = try result.payload.sourceDesignDigest.map {
            try ContentDigest(algorithm: .sha256, hexadecimalValue: $0)
        }
        let payload = LogicLoweringFoundationPayload(
            sourceDesignDigest: sourceDigest,
            executionDesign: result.payload.executionDesign,
            loweredSignalCount: result.payload.loweredSignalCount,
            loweredNodeCount: result.payload.loweredNodeCount
        )
        let producer = try ProducerIdentity(
            kind: .engine,
            identifier: "LogicLowering",
            version: "1"
        )
        let provenance = try ExecutionProvenance(
            producer: producer,
            inputs: request.inputs,
            designRevision: request.design.designRevision ?? request.design.artifact.digest,
            startedAt: startedAt,
            completedAt: completedAt
        )
        return LogicLoweringFoundationResult(
            runID: request.runID,
            status: result.status,
            payload: payload,
            artifacts: result.artifacts,
            diagnostics: result.diagnostics,
            provenance: provenance
        )
    }
}
