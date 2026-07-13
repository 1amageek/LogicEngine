import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR
import XcircuitePackage

/// Synthesis output projected onto the Foundation evidence contracts.
public struct LogicSynthesisFoundationResult: Sendable, Hashable, Codable,
    ArtifactProducing, DiagnosticReporting, EvidenceProviding
{
    public let schemaVersion: SchemaVersion
    public let runID: String
    public let status: LogicExecutionStatus
    public let payload: LogicSynthesisFoundationPayload
    public let artifacts: [ArtifactReference]
    public let diagnostics: [DesignDiagnostic]
    public let evidence: EvidenceManifest

    public init(
        runID: String,
        status: LogicExecutionStatus,
        payload: LogicSynthesisFoundationPayload,
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
        legacy: XcircuiteEngineResultEnvelope<LogicSynthesisPayload>,
        request: LogicSynthesisFoundationRequest,
        bridge: LogicFoundationArtifactBridge = LogicFoundationArtifactBridge()
    ) throws {
        let producer = try Self.producer(from: legacy.metadata)
        let artifacts = try legacy.artifacts.map {
            try bridge.foundationReference(
                from: $0,
                defaultKind: .netlist,
                defaultFormat: .json,
                producer: producer
            )
        }
        let diagnostics = try legacy.diagnostics.map {
            try bridge.foundationDiagnostic(from: $0, namespace: "logic.synthesis")
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
        from legacy: LogicSynthesisPayload,
        producer: ProducerIdentity,
        bridge: LogicFoundationArtifactBridge
    ) throws -> LogicSynthesisFoundationPayload {
        let mappedDesign = try legacy.mappedDesign.map { reference in
            let artifact = try bridge.foundationReference(
                from: reference.artifact,
                defaultKind: .netlist,
                defaultFormat: .json,
                producer: producer
            )
            let designRevision = try ContentDigest(
                algorithm: .sha256,
                hexadecimalValue: reference.designDigest
            )
            return LogicFoundationDesignReference(
                artifact: artifact,
                topDesignName: reference.topDesignName,
                designRevision: designRevision
            )
        }
        return LogicSynthesisFoundationPayload(
            mappedDesign: mappedDesign,
            mappedCellCount: legacy.mappedCellCount,
            loweredNodeCount: legacy.loweredNodeCount,
            optimizedNodeCount: legacy.optimizedNodeCount,
            totalArea: legacy.totalArea,
            totalPower: legacy.totalPower,
            provenance: try legacy.provenance.map {
                try bridge.foundationReference(
                    from: $0,
                    defaultKind: .report,
                    defaultFormat: .json,
                    producer: producer
                )
            },
            equivalenceRequest: try legacy.equivalenceRequest.map {
                try bridge.foundationReference(
                    from: $0,
                    defaultKind: .report,
                    defaultFormat: .json,
                    producer: producer
                )
            },
            equivalenceRequired: legacy.equivalenceRequired,
            acceptanceState: legacy.acceptanceState
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
