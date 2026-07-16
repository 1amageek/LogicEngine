import Foundation
import LogicEngineCore
import LogicIR
import CircuiteFoundation

public struct LogicBoundedTemporalEquivalenceRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = SchemaVersion.v1

    public var schemaVersion: SchemaVersion
    public var runID: String
    public var inputs: [ArtifactReference]
    public var referenceDesign: LogicDesignArtifact
    public var implementationDesign: LogicDesignArtifact
    public var stimulus: ArtifactReference
    public var outputSignals: [String]
    public var sampleLimit: Int
    public var artifactDirectory: String?

    public init(
        runID: String,
        inputs: [ArtifactReference] = [],
        referenceDesign: LogicDesignArtifact,
        implementationDesign: LogicDesignArtifact,
        stimulus: ArtifactReference,
        outputSignals: [String] = [],
        sampleLimit: Int,
        artifactDirectory: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        var allInputs: [ArtifactReference] = []
        for artifact in [referenceDesign.artifact, implementationDesign.artifact, stimulus] + inputs
            where !allInputs.contains(artifact) {
            allInputs.append(artifact)
        }
        self.inputs = allInputs
        self.referenceDesign = referenceDesign
        self.implementationDesign = implementationDesign
        self.stimulus = stimulus
        self.outputSignals = outputSignals
        self.sampleLimit = sampleLimit
        self.artifactDirectory = artifactDirectory
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicExecutionContractError.invalidRequest(
                "unsupported bounded temporal equivalence request schema version \(schemaVersion)"
            )
        }
        guard !runID.isEmpty else {
            throw LogicExecutionContractError.invalidRequest(
                "bounded temporal equivalence run ID is empty"
            )
        }
        guard referenceDesign.topDesignName == implementationDesign.topDesignName,
              !referenceDesign.topDesignName.isEmpty else {
            throw LogicExecutionContractError.invalidRequest(
                "bounded temporal equivalence designs must use the same top design"
            )
        }
        guard referenceDesign.designRevision != nil,
              implementationDesign.designRevision != nil else {
            throw LogicExecutionContractError.invalidRequest(
                "bounded temporal equivalence designs must carry digests"
            )
        }
        guard !stimulus.locator.location.value.isEmpty else {
            throw LogicExecutionContractError.invalidRequest(
                "bounded temporal equivalence stimulus path is empty"
            )
        }
        guard sampleLimit > 0 else {
            throw LogicExecutionContractError.invalidRequest(
                "bounded temporal equivalence sample limit must be positive"
            )
        }
        guard outputSignals.allSatisfy({ !$0.isEmpty }),
              Set(outputSignals).count == outputSignals.count else {
            throw LogicExecutionContractError.invalidRequest(
                "bounded temporal equivalence output signal names must be unique and non-empty"
            )
        }
        guard inputs.contains(referenceDesign.artifact),
              inputs.contains(implementationDesign.artifact),
              inputs.contains(stimulus) else {
            throw LogicExecutionContractError.invalidRequest(
                "equivalence design and stimulus artifacts must be present in the input set"
            )
        }
    }
}
