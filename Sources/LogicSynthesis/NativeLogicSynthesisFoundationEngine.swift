import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR
import PDKCore
import PowerIntent
import TimingCore

public struct NativeLogicSynthesisFoundationEngine: LogicSynthesisFoundationEngine {
    public let engine: any LogicSynthesisExecuting

    public init(
        engine: any LogicSynthesisExecuting = NativeLogicSynthesisEngine()
    ) {
        self.engine = engine
    }

    public func execute(
        _ request: LogicSynthesisFoundationRequest
    ) async throws -> LogicSynthesisFoundationResult {
        try request.validate()
        let libraries = request.libraries.map { library in
            TimingLibraryReference(
                artifact: library.artifact,
                cornerIDs: library.cornerIDs
            )
        }
        let powerIntent = request.powerIntent.map {
            PowerIntentReference(
                artifact: $0.locator,
                designDigest: request.powerIntentDesignRevision?.hexadecimalValue
                    ?? request.design.artifact.digest.hexadecimalValue
            )
        }
        let synthesisRequest = LogicSynthesisRequest(
            runID: request.runID,
            inputs: request.inputs,
            design: request.design,
            libraries: libraries,
            constraints: TimingConstraintReference(
                artifact: request.constraints,
                modeIDs: request.constraintModeIDs
            ),
            pdk: PDKReference(
                manifest: request.pdkManifest,
                processID: request.processID,
                version: request.pdkVersion,
                digest: request.pdkDigest.hexadecimalValue
            ),
            powerIntent: powerIntent,
            artifactDirectory: request.artifactDirectory
        )
        let result = try await engine.execute(synthesisRequest)
        let producer = try ProducerIdentity(kind: .engine, identifier: "LogicSynthesis", version: "1")
        let provenance = try ExecutionProvenance(
            producer: producer,
            inputs: request.inputs,
            designRevision: request.design.designRevision ?? request.design.artifact.digest,
            startedAt: Date(),
            completedAt: Date()
        )
        return LogicSynthesisFoundationResult(
            runID: request.runID,
            status: result.status,
            payload: LogicSynthesisFoundationPayload(
                mappedDesign: result.payload.mappedDesign,
                mappedCellCount: result.payload.mappedCellCount,
                loweredNodeCount: result.payload.loweredNodeCount,
                optimizedNodeCount: result.payload.optimizedNodeCount,
                totalArea: result.payload.totalArea,
                totalPower: result.payload.totalPower,
                provenance: result.payload.provenance,
                equivalenceRequest: result.payload.equivalenceRequest,
                equivalenceRequired: result.payload.equivalenceRequired,
                acceptanceState: result.payload.acceptanceState
            ),
            artifacts: result.artifacts,
            diagnostics: result.diagnostics,
            provenance: provenance
        )
    }
}
