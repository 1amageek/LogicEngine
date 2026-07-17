import Foundation
import CircuiteFoundation
import LogicEngineCore
import LogicIR

public struct LogicLoweringResult: Sendable, Hashable, Codable, ArtifactProducing,
    DiagnosticReporting, EvidenceProviding
{
    public var schemaVersion: SchemaVersion
    public var runID: String
    public var status: LogicExecutionStatus
    public var document: LogicDesignDocument?
    public var payload: LogicLoweringPayload
    public var artifacts: [ArtifactReference] {
        didSet { evidence = EvidenceManifest(id: evidence.id, provenance: provenance, artifacts: artifacts) }
    }
    public var diagnostics: [DesignDiagnostic]
    public var provenance: ExecutionProvenance {
        didSet { evidence = EvidenceManifest(id: evidence.id, provenance: provenance, artifacts: artifacts) }
    }
    public private(set) var evidence: EvidenceManifest

    public init(
        schemaVersion: SchemaVersion = LogicLoweringRequest.currentSchemaVersion,
        runID: String,
        status: LogicExecutionStatus,
        document: LogicDesignDocument? = nil,
        payload: LogicLoweringPayload = LogicLoweringPayload(),
        artifacts: [ArtifactReference] = [],
        diagnostics: [DesignDiagnostic] = [],
        provenance: ExecutionProvenance
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.document = document
        self.payload = payload
        self.artifacts = artifacts
        self.diagnostics = diagnostics
        self.provenance = provenance
        self.evidence = EvidenceManifest(provenance: provenance, artifacts: artifacts)
    }
}
