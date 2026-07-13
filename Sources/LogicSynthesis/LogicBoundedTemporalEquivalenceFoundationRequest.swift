import CircuiteFoundation
import Foundation
import LogicEngineCore

/// Foundation-native bounded trace equivalence inputs.
public struct LogicBoundedTemporalEquivalenceFoundationRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = SchemaVersion.v1

    public let schemaVersion: SchemaVersion
    public let runID: String
    public let inputs: [ArtifactReference]
    public let referenceDesign: LogicFoundationDesignReference
    public let implementationDesign: LogicFoundationDesignReference
    public let stimulus: ArtifactReference
    public let outputSignals: [String]
    public let sampleLimit: Int
    public let artifactDirectory: String?

    public init(
        runID: String,
        referenceDesign: LogicFoundationDesignReference,
        implementationDesign: LogicFoundationDesignReference,
        stimulus: ArtifactReference,
        outputSignals: [String] = [],
        sampleLimit: Int,
        inputs: [ArtifactReference] = [],
        artifactDirectory: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.referenceDesign = referenceDesign
        self.implementationDesign = implementationDesign
        self.stimulus = stimulus
        self.outputSignals = outputSignals
        self.sampleLimit = sampleLimit
        self.artifactDirectory = artifactDirectory
        var allInputs: [ArtifactReference] = []
        for artifact in [referenceDesign.artifact, implementationDesign.artifact, stimulus] + inputs
            where !allInputs.contains(artifact) {
            allInputs.append(artifact)
        }
        self.inputs = allInputs
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicFoundationBoundaryError.invalidRequest(
                "unsupported bounded equivalence request schema version \(schemaVersion)"
            )
        }
        guard !runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicFoundationBoundaryError.invalidRequest("run ID is empty")
        }
        guard !referenceDesign.topDesignName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              referenceDesign.topDesignName == implementationDesign.topDesignName else {
            throw LogicFoundationBoundaryError.invalidRequest(
                "reference and implementation designs must use the same non-empty top design"
            )
        }
        guard sampleLimit > 0 else {
            throw LogicFoundationBoundaryError.invalidRequest("sample limit must be positive")
        }
        guard outputSignals.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }), Set(outputSignals).count == outputSignals.count else {
            throw LogicFoundationBoundaryError.invalidRequest(
                "output signal names must be unique and non-empty"
            )
        }
        guard inputs.contains(referenceDesign.artifact),
              inputs.contains(implementationDesign.artifact),
              inputs.contains(stimulus) else {
            throw LogicFoundationBoundaryError.invalidRequest(
                "equivalence design and stimulus artifacts must be present in the input set"
            )
        }
    }
}
