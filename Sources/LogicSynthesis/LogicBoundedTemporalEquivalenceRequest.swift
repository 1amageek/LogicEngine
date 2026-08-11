import Foundation
import LogicEngineCore
import LogicIR
import CircuiteFoundation

public struct LogicBoundedTemporalEquivalenceRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = SchemaVersion.v2

    public var schemaVersion: SchemaVersion
    public var runID: String
    public var inputs: [ArtifactReference]
    public var inputBindings: [LogicArtifactBinding]
    public var referenceDesign: LogicDesignReference
    public var implementationDesign: LogicDesignReference
    public var stimulus: LogicArtifactBinding
    public var outputSignals: [String]
    public var sampleLimit: Int
    public var artifactDirectory: String?

    public init(
        runID: String,
        inputBindings: [LogicArtifactBinding],
        referenceDesign: LogicDesignReference,
        implementationDesign: LogicDesignReference,
        stimulus: LogicArtifactBinding,
        outputSignals: [String] = [],
        sampleLimit: Int,
        artifactDirectory: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        var allBindings: [LogicArtifactBinding] = []
        for binding in inputBindings + [stimulus]
            where !allBindings.contains(where: { $0.reference == binding.reference }) {
            allBindings.append(binding)
        }
        self.inputs = allBindings.map(\.reference)
        self.inputBindings = allBindings
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
        do {
            _ = try ContentDigest(algorithm: .sha256, hexadecimalValue: referenceDesign.designDigest)
            _ = try ContentDigest(algorithm: .sha256, hexadecimalValue: implementationDesign.designDigest)
        } catch {
            throw LogicExecutionContractError.invalidRequest(
                "bounded temporal equivalence designs must carry valid SHA-256 digests"
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
              inputs.contains(stimulus.reference) else {
            throw LogicExecutionContractError.invalidRequest(
                "equivalence design and stimulus artifacts must be present in the input set"
            )
        }
        guard inputBindings.map(\.reference) == inputs else {
            throw LogicExecutionContractError.invalidRequest(
                "input bindings do not match the content-only input lineage"
            )
        }
        _ = try LogicArtifactBinding.require(referenceDesign.artifact, in: inputBindings)
        _ = try LogicArtifactBinding.require(implementationDesign.artifact, in: inputBindings)
    }
}
