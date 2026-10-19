import CircuiteFoundation
import LogicEngineCore

public struct LogicEquivalenceRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = SchemaVersion.v3
    public let schemaVersion: SchemaVersion
    public let runID: String
    public let receipt: LogicArtifactBinding
    public let limits: LogicRuntimeLimits
    public init(runID: String, receipt: LogicArtifactBinding, limits: LogicRuntimeLimits) {
        schemaVersion = Self.currentSchemaVersion; self.runID = runID; self.receipt = receipt; self.limits = limits
    }
}
