import CircuiteFoundation
import Foundation
import LogicEngineCore

/// Foundation-native inputs for RTL-to-execution-graph lowering.
public struct LogicLoweringFoundationRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = SchemaVersion.v1

    public let schemaVersion: SchemaVersion
    public let runID: String
    public let inputs: [ArtifactReference]
    public let design: LogicFoundationDesignReference
    public let artifactDirectory: String?

    public init(
        runID: String,
        design: LogicFoundationDesignReference,
        inputs: [ArtifactReference] = [],
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
            throw LogicFoundationBoundaryError.invalidRequest(
                "unsupported lowering request schema version \(schemaVersion)"
            )
        }
        guard !runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicFoundationBoundaryError.invalidRequest("run ID is empty")
        }
        guard !design.topDesignName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicFoundationBoundaryError.invalidRequest("top design name is empty")
        }
        guard inputs.contains(design.artifact) else {
            throw LogicFoundationBoundaryError.invalidRequest(
                "design artifact is missing from the input set"
            )
        }
    }
}
