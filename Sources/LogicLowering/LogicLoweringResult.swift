import Foundation
import CircuiteFoundation
import LogicEngineCore
import LogicIR

public struct LogicLoweringResult: Sendable, Hashable, Codable, ArtifactProducing,
    DiagnosticReporting, EvidenceProviding
{
    public let schemaVersion: SchemaVersion
    public let runID: String
    public let status: LogicExecutionStatus
    public let document: LogicDesignDocument?
    public let payload: LogicLoweringPayload
    public let artifactBindings: [LogicArtifactBinding]
    public var artifacts: [ArtifactReference] { artifactBindings.map(\.reference) }
    public let diagnostics: [DesignDiagnostic]
    public let provenance: ExecutionProvenance
    public let evidence: EvidenceManifest

    public init(
        schemaVersion: SchemaVersion = LogicLoweringRequest.currentSchemaVersion,
        runID: String,
        status: LogicExecutionStatus,
        document: LogicDesignDocument? = nil,
        payload: LogicLoweringPayload = LogicLoweringPayload(),
        artifactBindings: [LogicArtifactBinding] = [],
        diagnostics: [DesignDiagnostic] = [],
        provenance: ExecutionProvenance
    ) throws {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.document = document
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
