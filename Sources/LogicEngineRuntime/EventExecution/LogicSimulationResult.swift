import CircuiteFoundation
import LogicEngineCore
import LogicIR

public struct LogicSimulationResult: Sendable, Hashable, Codable, ArtifactProducing, DiagnosticReporting, EvidenceProviding {
    public let schemaVersion: SchemaVersion
    public let runID: String
    public let status: LogicExecutionStatus
    public let acceptance: LogicArtifactBinding
    public let assessment: LogicSimulationAssessment
    public let observations: [LogicSimulationObservationRecord]
    public let artifactBindings: [LogicArtifactBinding]
    public var artifacts: [ArtifactReference] { artifactBindings.map(\.reference) }
    public let diagnostics: [DesignDiagnostic]
    public let evidence: EvidenceManifest
    public var provenance: ExecutionProvenance { evidence.provenance }
    internal init(runID: String, observations: [LogicSimulationObservationRecord], artifacts: [LogicArtifactBinding],
                  acceptance: LogicArtifactBinding, assessment: LogicSimulationAssessment,
                  provenance: ExecutionProvenance) throws {
        schemaVersion = LogicSimulationRequest.currentSchemaVersion; self.runID = runID; status = .completed
        self.observations = observations; artifactBindings = artifacts; diagnostics = []
        self.acceptance = acceptance; self.assessment = assessment
        evidence = try LogicEvidenceManifestFactory.make(provenance: provenance, artifacts: artifacts.map(\.reference))
    }
}
