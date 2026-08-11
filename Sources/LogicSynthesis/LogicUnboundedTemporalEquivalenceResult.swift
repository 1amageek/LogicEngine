import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR

public struct LogicUnboundedTemporalEquivalenceResult: Sendable, Hashable, Codable,
    ArtifactProducing, DiagnosticReporting, EvidenceProviding
{
    public let schemaVersion: SchemaVersion
    public let runID: String
    public let status: LogicIR.LogicExecutionStatus
    public let payload: LogicUnboundedTemporalEquivalencePayload
    public let artifactBindings: [LogicArtifactBinding]
    public var artifacts: [ArtifactReference] { artifactBindings.map(\.reference) }
    public let diagnostics: [DesignDiagnostic]
    public let evidence: EvidenceManifest

    public init(
        runID: String,
        status: LogicIR.LogicExecutionStatus,
        payload: LogicUnboundedTemporalEquivalencePayload,
        artifactBindings: [LogicArtifactBinding] = [],
        diagnostics: [DesignDiagnostic] = [],
        provenance: ExecutionProvenance,
        schemaVersion: SchemaVersion = LogicUnboundedTemporalEquivalenceRequest.currentSchemaVersion
    ) throws {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.payload = payload
        self.artifactBindings = artifactBindings
        self.diagnostics = diagnostics
        self.evidence = try LogicEvidenceManifestFactory.make(
            provenance: provenance,
            artifacts: artifactBindings.map(\.reference)
        )
    }
}
