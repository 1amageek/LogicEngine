import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR

public struct LogicSynthesisResult: Sendable, Hashable, Codable, ArtifactProducing, DiagnosticReporting, EvidenceProviding {
    public let schemaVersion: SchemaVersion
    public let runID: String
    public let status: LogicExecutionStatus
    public let diagnostics: [DesignDiagnostic]
    public let receipt: LogicArtifactBinding
    public let payload: LogicSynthesisReceipt
    public let provenance: ExecutionProvenance
    public let evidence: EvidenceManifest
    public var artifactBindings: [LogicArtifactBinding] { payload.artifacts + [receipt] }
    public var artifacts: [ArtifactReference] { artifactBindings.map(\.reference) }
    internal init(runID: String, receipt: LogicArtifactBinding, payload: LogicSynthesisReceipt,
                  provenance: ExecutionProvenance) throws {
        schemaVersion = LogicSynthesisRequest.currentSchemaVersion; self.runID = runID; status = .completed
        diagnostics = []; self.receipt = receipt; self.payload = payload; self.provenance = provenance
        evidence = try LogicEvidenceManifestFactory.make(provenance: provenance, artifacts: payload.artifacts.map(\.reference) + [receipt.reference])
    }
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, runID, status, diagnostics, receipt, payload, provenance, evidence
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(SchemaVersion.self, forKey: .schemaVersion)
        let status = try c.decode(LogicExecutionStatus.self, forKey: .status)
        let diagnostics = try c.decode([DesignDiagnostic].self, forKey: .diagnostics)
        guard version == LogicSynthesisRequest.currentSchemaVersion, status == .completed, diagnostics.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: c, debugDescription: "Unsupported actual-cell result")
        }
        try self.init(runID: c.decode(String.self, forKey: .runID), receipt: c.decode(LogicArtifactBinding.self, forKey: .receipt),
            payload: c.decode(LogicSynthesisReceipt.self, forKey: .payload), provenance: c.decode(ExecutionProvenance.self, forKey: .provenance))
        guard evidence == (try c.decode(EvidenceManifest.self, forKey: .evidence)),
              payload.producer == provenance.producer else {
            throw DecodingError.dataCorruptedError(forKey: .evidence, in: c, debugDescription: "Result evidence/producer binding differs")
        }
    }

}
