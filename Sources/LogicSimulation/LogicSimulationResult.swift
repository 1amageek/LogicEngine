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
    public let artifactBindings: [LogicArtifactBinding]
    public var artifacts: [ArtifactReference] { artifactBindings.map(\.reference) }
    public let diagnostics: [DesignDiagnostic]
    public let provenance: ExecutionProvenance
    public let evidence: EvidenceManifest

    public init(
        schemaVersion: SchemaVersion = LogicSimulationRequest.currentSchemaVersion,
        runID: String,
        status: LogicExecutionStatus,
        payload: LogicSimulationPayload,
        artifactBindings: [LogicArtifactBinding] = [],
        diagnostics: [DesignDiagnostic] = [],
        provenance: ExecutionProvenance
    ) throws {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.payload = payload
        self.artifactBindings = artifactBindings
        self.diagnostics = diagnostics
        self.provenance = provenance
        self.evidence = try LogicEvidenceManifestFactory.make(
            provenance: provenance,
            artifacts: artifactBindings.map(\.reference)
        )
    }
}
