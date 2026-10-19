import CircuiteFoundation
import LogicEngineCore

/// A replay observation; checked proof authority remains in the loaded owner.
public struct LogicEquivalenceResult: Sendable, Hashable, Codable {
    public let schemaVersion: SchemaVersion
    public let runID: String
    public let receipt: LogicArtifactBinding
    public let proof: LogicArtifactBinding
    public let proofKind: String
    public let equivalent: Bool
    internal init(runID: String, receipt: LogicArtifactBinding, proof: LogicArtifactBinding, proofKind: String) {
        schemaVersion = LogicEquivalenceRequest.currentSchemaVersion; self.runID = runID
        self.receipt = receipt; self.proof = proof; self.proofKind = proofKind; equivalent = true
    }
}
