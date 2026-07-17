import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR

public struct LogicBoundedTemporalEquivalenceResult: Sendable, Hashable, Codable,
    ArtifactProducing, DiagnosticReporting, EvidenceProviding
{
    public let schemaVersion: SchemaVersion
    public let runID: String
    public let status: LogicIR.LogicExecutionStatus
    public let diagnostics: [DesignDiagnostic]
    public let artifacts: [ArtifactReference]
    public let provenance: ExecutionProvenance
    public let payload: LogicBoundedTemporalEquivalencePayload
    public let evidence: EvidenceManifest

    public init(
        schemaVersion: SchemaVersion,
        runID: String,
        status: LogicIR.LogicExecutionStatus,
        diagnostics: [DesignDiagnostic],
        artifacts: [ArtifactReference],
        provenance: ExecutionProvenance,
        payload: LogicBoundedTemporalEquivalencePayload
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.diagnostics = diagnostics
        self.artifacts = artifacts
        self.provenance = provenance
        self.payload = payload
        self.evidence = EvidenceManifest(provenance: provenance, artifacts: artifacts)
    }
}
