import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR

public struct NativeLogicSimulationFoundationEngine: LogicSimulationFoundationEngine {
    public let engine: any LogicSimulationExecuting

    public init(
        engine: any LogicSimulationExecuting = NativeLogicSimulationEngine()
    ) {
        self.engine = engine
    }

    public func execute(
        _ request: LogicSimulationFoundationRequest
    ) async throws -> LogicSimulationFoundationResult {
        try request.validate()
        let domainRequest = LogicSimulationRequest(
            runID: request.runID,
            inputs: request.inputs,
            design: request.design,
            stimulus: request.stimulus,
            seed: request.seed,
            waveformFormat: request.waveformFormat,
            artifactDirectory: request.artifactDirectory
        )
        let result = try await engine.execute(domainRequest)
        let producer = try ProducerIdentity(kind: .engine, identifier: "LogicSimulation", version: "1")
        let provenance = try ExecutionProvenance(
            producer: producer,
            inputs: request.inputs,
            designRevision: request.design.designRevision ?? request.design.artifact.digest,
            randomSeed: request.seed,
            startedAt: Date(),
            completedAt: Date()
        )
        return LogicSimulationFoundationResult(
            runID: request.runID,
            status: result.status,
            payload: LogicSimulationFoundationPayload(
                traceCount: result.payload.traceCount,
                assertionFailureCount: result.payload.assertionFailureCount,
                eventCount: result.payload.eventCount,
                waveform: result.payload.waveform,
                assertionReport: result.payload.assertionReport,
                cancellationRecord: result.payload.cancellationRecord,
                finalValues: result.payload.finalValues
            ),
            artifacts: result.artifacts,
            diagnostics: result.diagnostics,
            provenance: provenance
        )
    }
}
