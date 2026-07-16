import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR

public struct LogicUnboundedTemporalEquivalenceFoundationResult: Sendable, Hashable, Codable,
    ArtifactProducing, DiagnosticReporting, EvidenceProviding
{
    public let schemaVersion: SchemaVersion
    public let runID: String
    public let status: LogicIR.LogicExecutionStatus
    public let payload: LogicUnboundedTemporalEquivalenceFoundationPayload
    public let artifacts: [ArtifactReference]
    public let diagnostics: [DesignDiagnostic]
    public let evidence: EvidenceManifest

    public init(
        runID: String,
        status: LogicIR.LogicExecutionStatus,
        payload: LogicUnboundedTemporalEquivalenceFoundationPayload,
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
}
