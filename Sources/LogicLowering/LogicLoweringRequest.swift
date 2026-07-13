import CircuiteFoundation
import Foundation
import LogicIR
import LogicEngineCore

public struct LogicLoweringRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [ArtifactReference]
    public var design: LogicFoundationDesignReference
    public var artifactDirectory: String?

    public init(
        runID: String,
        inputs: [ArtifactReference],
        design: LogicFoundationDesignReference,
        artifactDirectory: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.inputs = inputs
        self.design = design
        self.artifactDirectory = artifactDirectory
    }
}
