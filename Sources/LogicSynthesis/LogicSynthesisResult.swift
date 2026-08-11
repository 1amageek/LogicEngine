import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR

public struct LogicSynthesisResult: Sendable, Hashable, Codable, ArtifactProducing,
    DiagnosticReporting, EvidenceProviding
{
    public let schemaVersion: SchemaVersion
    public let runID: String
    public let status: LogicIR.LogicExecutionStatus
    public let diagnostics: [DesignDiagnostic]
    public let artifactBindings: [LogicArtifactBinding]
    public var artifacts: [ArtifactReference] { artifactBindings.map(\.reference) }
    public let provenance: ExecutionProvenance
    public let payload: LogicSynthesisPayload
    public let evidence: EvidenceManifest

    public init(
        schemaVersion: SchemaVersion,
        runID: String,
        status: LogicIR.LogicExecutionStatus,
        diagnostics: [DesignDiagnostic],
        artifactBindings: [LogicArtifactBinding],
        provenance: ExecutionProvenance,
        payload: LogicSynthesisPayload
    ) throws {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.diagnostics = diagnostics
        self.artifactBindings = artifactBindings
        self.provenance = provenance
        self.payload = payload
        self.evidence = try LogicEvidenceManifestFactory.make(
            provenance: provenance,
            artifacts: artifactBindings.map(\.reference)
        )
    }
}
