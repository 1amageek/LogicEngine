import Foundation
import LogicEngineCore
import LogicIR
import XcircuitePackage

public struct LogicBoundedTemporalEquivalenceRequest: XcircuiteEngineRequest {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [XcircuiteFileReference]
    public var referenceDesign: LogicDesignReference
    public var implementationDesign: LogicDesignReference
    public var stimulus: XcircuiteFileReference
    public var outputSignals: [String]
    public var sampleLimit: Int
    public var artifactDirectory: String?

    public init(
        runID: String,
        inputs: [XcircuiteFileReference],
        referenceDesign: LogicDesignReference,
        implementationDesign: LogicDesignReference,
        stimulus: XcircuiteFileReference,
        outputSignals: [String] = [],
        sampleLimit: Int,
        artifactDirectory: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.inputs = inputs
        self.referenceDesign = referenceDesign
        self.implementationDesign = implementationDesign
        self.stimulus = stimulus
        self.outputSignals = outputSignals
        self.sampleLimit = sampleLimit
        self.artifactDirectory = artifactDirectory
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicExecutionError.invalidArtifact(
                "unsupported bounded temporal equivalence request schema version \(schemaVersion)"
            )
        }
        guard !runID.isEmpty else {
            throw LogicExecutionError.invalidArtifact("bounded temporal equivalence run ID is empty")
        }
        guard referenceDesign.topDesignName == implementationDesign.topDesignName,
              !referenceDesign.topDesignName.isEmpty else {
            throw LogicExecutionError.invalidDesign(
                "bounded temporal equivalence designs must use the same top design"
            )
        }
        guard !referenceDesign.designDigest.isEmpty,
              !implementationDesign.designDigest.isEmpty else {
            throw LogicExecutionError.invalidArtifact(
                "bounded temporal equivalence designs must carry digests"
            )
        }
        guard !stimulus.path.isEmpty else {
            throw LogicExecutionError.invalidArtifact("bounded temporal equivalence stimulus path is empty")
        }
        guard sampleLimit > 0 else {
            throw LogicExecutionError.invalidArtifact("bounded temporal equivalence sample limit must be positive")
        }
        guard outputSignals.allSatisfy({ !$0.isEmpty }),
              Set(outputSignals).count == outputSignals.count else {
            throw LogicExecutionError.invalidArtifact(
                "bounded temporal equivalence output signal names must be unique and non-empty"
            )
        }
    }
}
