import CircuiteFoundation
import Foundation
import LogicIR
import LogicEngineCore

public struct LogicLoweringRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = SchemaVersion.v1

    public var schemaVersion: SchemaVersion
    public var runID: String
    public var inputs: [ArtifactReference]
    public var design: LogicDesignArtifact
    public var artifactDirectory: String?

    public init(
        runID: String,
        inputs: [ArtifactReference] = [],
        design: LogicDesignArtifact,
        artifactDirectory: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        var allInputs: [ArtifactReference] = []
        for artifact in [design.artifact] + inputs where !allInputs.contains(artifact) {
            allInputs.append(artifact)
        }
        self.inputs = allInputs
        self.design = design
        self.artifactDirectory = artifactDirectory
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicExecutionContractError.invalidRequest(
                "unsupported lowering request schema version \(schemaVersion)"
            )
        }
        guard !runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicExecutionContractError.invalidRequest("run ID is empty")
        }
        guard !design.topDesignName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicExecutionContractError.invalidRequest("top design name is empty")
        }
        guard inputs.contains(design.artifact) else {
            throw LogicExecutionContractError.invalidRequest(
                "design artifact is missing from the input set"
            )
        }
    }
}
