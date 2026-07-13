import Foundation
import CircuiteFoundation
import LogicEngineCore
import LogicIR
import LogicSimulation

public struct NativeLogicBoundedTemporalEquivalenceFoundationEngine:
    LogicBoundedTemporalEquivalenceFoundationEngine
{
    public let engine: any LogicBoundedTemporalEquivalenceExecuting

    public init(
        engine: any LogicBoundedTemporalEquivalenceExecuting = NativeLogicBoundedTemporalEquivalenceEngine()
    ) {
        self.engine = engine
    }

    public func execute(
        _ request: LogicBoundedTemporalEquivalenceFoundationRequest
    ) async throws -> LogicBoundedTemporalEquivalenceFoundationResult {
        try request.validate()
        let legacyRequest = LogicBoundedTemporalEquivalenceRequest(
            runID: request.runID,
            inputs: request.inputs,
            referenceDesign: request.referenceDesign,
            implementationDesign: request.implementationDesign,
            stimulus: request.stimulus,
            outputSignals: request.outputSignals,
            sampleLimit: request.sampleLimit,
            artifactDirectory: request.artifactDirectory
        )
        let result = try await engine.execute(legacyRequest)
        let producer = try ProducerIdentity(kind: .engine, identifier: "LogicBoundedTemporalEquivalence", version: "1")
        let provenance = try ExecutionProvenance(
            producer: producer,
            inputs: request.inputs,
            designRevision: request.implementationDesign.designRevision ?? request.implementationDesign.artifact.digest,
            startedAt: Date(),
            completedAt: Date()
        )
        return LogicBoundedTemporalEquivalenceFoundationResult(
            runID: request.runID,
            status: result.status,
            payload: LogicBoundedTemporalEquivalenceFoundationPayload(
                proofStatus: result.payload.proofStatus,
                comparedSampleCount: result.payload.comparedSampleCount,
                mismatchCount: result.payload.mismatchCount,
                outputSignals: result.payload.outputSignals,
                referenceSimulationReport: result.payload.referenceSimulationReport,
                implementationSimulationReport: result.payload.implementationSimulationReport,
                equivalenceReport: result.payload.equivalenceReport,
                counterexample: result.payload.counterexample
            ),
            artifacts: result.artifacts,
            diagnostics: result.diagnostics,
            provenance: provenance
        )
    }
}
