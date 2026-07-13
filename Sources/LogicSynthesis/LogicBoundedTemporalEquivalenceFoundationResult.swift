import CircuiteFoundation
import Foundation
import LogicEngineCore
import XcircuitePackage

/// Bounded equivalence output projected onto the Foundation evidence contracts.
public struct LogicBoundedTemporalEquivalenceFoundationResult: Sendable, Hashable, Codable,
    ArtifactProducing, DiagnosticReporting, EvidenceProviding
{
    public let schemaVersion: SchemaVersion
    public let runID: String
    public let status: LogicExecutionStatus
    public let payload: LogicBoundedTemporalEquivalenceFoundationPayload
    public let artifacts: [ArtifactReference]
    public let diagnostics: [DesignDiagnostic]
    public let evidence: EvidenceManifest

    public init(
        runID: String,
        status: LogicExecutionStatus,
        payload: LogicBoundedTemporalEquivalenceFoundationPayload,
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
        legacy: XcircuiteEngineResultEnvelope<LogicBoundedTemporalEquivalencePayload>,
        request: LogicBoundedTemporalEquivalenceFoundationRequest,
        bridge: LogicFoundationArtifactBridge = LogicFoundationArtifactBridge()
    ) throws {
        let producer = try Self.producer(from: legacy.metadata)
        let artifacts = try legacy.artifacts.map {
            try bridge.foundationReference(
                from: $0,
                defaultKind: .report,
                defaultFormat: .json,
                producer: producer
            )
        }
        let diagnostics = try legacy.diagnostics.map {
            try bridge.foundationDiagnostic(from: $0, namespace: "logic.equivalence")
        }
        let payload = try Self.payload(
            from: legacy.payload,
            producer: producer,
            bridge: bridge
        )
        let provenance = try ExecutionProvenance(
            producer: producer,
            inputs: request.inputs,
            designRevision: request.implementationDesign.designRevision
                ?? request.implementationDesign.artifact.digest,
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
        from legacy: LogicBoundedTemporalEquivalencePayload,
        producer: ProducerIdentity,
        bridge: LogicFoundationArtifactBridge
    ) throws -> LogicBoundedTemporalEquivalenceFoundationPayload {
        func reference(
            _ value: XcircuiteFileReference?,
            kind: ArtifactKind = .report,
            format: ArtifactFormat = .json
        ) throws -> ArtifactReference? {
            try value.map {
                try bridge.foundationReference(
                    from: $0,
                    defaultKind: kind,
                    defaultFormat: format,
                    producer: producer
                )
            }
        }
        return LogicBoundedTemporalEquivalenceFoundationPayload(
            proofStatus: legacy.proofStatus,
            comparedSampleCount: legacy.comparedSampleCount,
            mismatchCount: legacy.mismatchCount,
            outputSignals: legacy.outputSignals,
            referenceSimulationReport: try reference(legacy.referenceSimulationReport),
            implementationSimulationReport: try reference(legacy.implementationSimulationReport),
            equivalenceReport: try reference(legacy.equivalenceReport),
            counterexample: try reference(legacy.counterexample)
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
