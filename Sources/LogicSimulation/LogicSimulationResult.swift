import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR

public struct LogicSimulationResult: Sendable, Hashable, Codable, ArtifactProducing,
    DiagnosticReporting, EvidenceProviding
{
    public let schemaVersion: SchemaVersion
    public let runID: String
    public let status: LogicExecutionStatus
    public let payload: LogicSimulationPayload
    public let artifacts: [ArtifactReference]
    public let diagnostics: [DesignDiagnostic]
    public let provenance: ExecutionProvenance
    public let evidence: EvidenceManifest

    public init(
        schemaVersion: SchemaVersion = LogicSimulationRequest.currentSchemaVersion,
        runID: String,
        status: LogicExecutionStatus,
        payload: LogicSimulationPayload,
        artifacts: [ArtifactReference] = [],
        diagnostics: [DesignDiagnostic] = [],
        provenance: ExecutionProvenance
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.payload = payload
        self.artifacts = artifacts
        self.diagnostics = diagnostics
        self.provenance = provenance
        self.evidence = EvidenceManifest(provenance: provenance, artifacts: artifacts)
    }
}
