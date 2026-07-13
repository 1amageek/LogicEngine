import CircuiteFoundation
import Foundation
import LogicEngineCore
import XcircuitePackage

/// Simulation output projected onto the Foundation evidence contracts.
public struct LogicSimulationFoundationResult: Sendable, Hashable, Codable,
    ArtifactProducing, DiagnosticReporting, EvidenceProviding
{
    public let schemaVersion: SchemaVersion
    public let runID: String
    public let status: LogicExecutionStatus
    public let payload: LogicSimulationFoundationPayload
    public let artifacts: [ArtifactReference]
    public let diagnostics: [DesignDiagnostic]
    public let evidence: EvidenceManifest

    public init(
        runID: String,
        status: LogicExecutionStatus,
        payload: LogicSimulationFoundationPayload,
        artifacts: [ArtifactReference] = [],
        diagnostics: [DesignDiagnostic] = [],
        provenance: ExecutionProvenance,
        schemaVersion: SchemaVersion = .v1
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.payload = payload
        self.artifacts = artifacts
        self.diagnostics = diagnostics
        self.evidence = EvidenceManifest(provenance: provenance, artifacts: artifacts)
    }

    init(
        legacy: XcircuiteEngineResultEnvelope<LogicSimulationPayload>,
        request: LogicSimulationFoundationRequest,
        bridge: LogicFoundationArtifactBridge = LogicFoundationArtifactBridge()
    ) throws {
        let producer = try Self.producer(from: legacy.metadata)
        let artifacts = try legacy.artifacts.map {
            try bridge.foundationReference(
                from: $0,
                defaultKind: .waveform,
                defaultFormat: .vcd,
                producer: producer
            )
        }
        let diagnostics = try legacy.diagnostics.map {
            try bridge.foundationDiagnostic(from: $0, namespace: "logic.simulation")
        }
        let payload = try Self.payload(
            from: legacy.payload,
            producer: producer,
            bridge: bridge
        )
        let provenance = try ExecutionProvenance(
            producer: producer,
            inputs: request.inputs,
            designRevision: request.design.designRevision ?? request.design.artifact.digest,
            randomSeed: request.seed,
            startedAt: legacy.metadata.startedAt,
            completedAt: legacy.metadata.completedAt
        )
        self.init(
            runID: legacy.runID,
            status: Self.status(for: legacy.status),
            payload: payload,
            artifacts: artifacts,
            diagnostics: diagnostics,
            provenance: provenance
        )
    }

    private static func producer(
        from metadata: XcircuiteEngineExecutionMetadata
    ) throws -> ProducerIdentity {
        do {
            return try ProducerIdentity(
                kind: .engine,
                identifier: metadata.engineID,
                version: metadata.implementationVersion,
                build: metadata.implementationID
            )
        } catch {
            throw LogicFoundationBoundaryError.invalidProducerIdentity(metadata.engineID)
        }
    }

    private static func payload(
        from legacy: LogicSimulationPayload,
        producer: ProducerIdentity,
        bridge: LogicFoundationArtifactBridge
    ) throws -> LogicSimulationFoundationPayload {
        LogicSimulationFoundationPayload(
            traceCount: legacy.traceCount,
            assertionFailureCount: legacy.assertionFailureCount,
            eventCount: legacy.eventCount,
            waveform: try legacy.waveform.map {
                try bridge.foundationReference(
                    from: $0,
                    defaultKind: .waveform,
                    defaultFormat: .vcd,
                    producer: producer
                )
            },
            assertionReport: try legacy.assertionReport.map {
                try bridge.foundationReference(
                    from: $0,
                    defaultKind: .report,
                    defaultFormat: .json,
                    producer: producer
                )
            },
            cancellationRecord: try legacy.cancellationRecord.map {
                try bridge.foundationReference(
                    from: $0,
                    defaultKind: .report,
                    defaultFormat: .json,
                    producer: producer
                )
            },
            finalValues: legacy.finalValues
        )
    }

    private static func status(for status: XcircuiteEngineExecutionStatus) -> LogicExecutionStatus {
        switch status {
        case .completed: return .completed
        case .failed: return .failed
        case .blocked: return .blocked
        case .cancelled: return .cancelled
        }
    }
}
