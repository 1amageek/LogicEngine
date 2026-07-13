import CircuiteFoundation
import Foundation
import LogicEngineCore

/// Foundation-native simulation inputs and artifact references.
public struct LogicSimulationFoundationRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = SchemaVersion.v1

    public let schemaVersion: SchemaVersion
    public let runID: String
    public let inputs: [ArtifactReference]
    public let design: LogicFoundationDesignReference
    public let stimulus: ArtifactReference?
    public let seed: UInt64?
    public let waveformFormat: LogicWaveformFormat
    public let artifactDirectory: String?

    public init(
        runID: String,
        design: LogicFoundationDesignReference,
        inputs: [ArtifactReference] = [],
        stimulus: ArtifactReference? = nil,
        seed: UInt64? = nil,
        waveformFormat: LogicWaveformFormat = .vcd,
        artifactDirectory: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        var allInputs: [ArtifactReference] = []
        for artifact in [design.artifact] + inputs where !allInputs.contains(artifact) {
            allInputs.append(artifact)
        }
        if let stimulus, !allInputs.contains(stimulus) {
            allInputs.append(stimulus)
        }
        self.inputs = allInputs
        self.design = design
        self.stimulus = stimulus
        self.seed = seed
        self.waveformFormat = waveformFormat
        self.artifactDirectory = artifactDirectory
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicFoundationBoundaryError.invalidRequest(
                "unsupported simulation request schema version \(schemaVersion)"
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
        if let stimulus, !inputs.contains(stimulus) {
            throw LogicFoundationBoundaryError.invalidRequest(
                "stimulus artifact is missing from the input set"
            )
        }
    }
}
