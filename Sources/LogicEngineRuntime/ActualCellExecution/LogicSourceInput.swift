import LogicEngineCore

public struct LogicSourceInput: Sendable, Hashable, Codable {
    public let logicalName: String
    public let artifact: LogicArtifactBinding
    public init(logicalName: String, artifact: LogicArtifactBinding) {
        self.logicalName = logicalName; self.artifact = artifact
    }
}
