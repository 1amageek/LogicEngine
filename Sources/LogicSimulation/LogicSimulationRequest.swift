import CircuiteFoundation
import Foundation
import LogicIR
import LogicEngineCore

public struct LogicSimulationRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = SchemaVersion.v1

    public var schemaVersion: SchemaVersion
    public var runID: String
    public var inputs: [ArtifactReference]

    public var design: LogicDesignReference
    public var stimulus: ArtifactReference?
    public var seed: UInt64?
    public var waveformFormat: LogicWaveformFormat
    public var artifactDirectory: String?

    public init(
        runID: String,
        inputs: [ArtifactReference] = [],
        design: LogicDesignReference,
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
            throw LogicExecutionContractError.invalidRequest(
                "unsupported simulation request schema version \(schemaVersion)"
            )
        }
        guard !runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicExecutionContractError.invalidRequest("run ID is empty")
        }
        guard !design.topDesignName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicExecutionContractError.invalidRequest("top design name is empty")
        }
        do {
            _ = try ContentDigest(algorithm: .sha256, hexadecimalValue: design.designDigest)
        } catch {
            throw LogicExecutionContractError.invalidRequest(
                "design must carry a valid SHA-256 digest"
            )
        }
        guard inputs.contains(design.artifact) else {
            throw LogicExecutionContractError.invalidRequest(
                "design artifact is missing from the input set"
            )
        }
        if let stimulus, !inputs.contains(stimulus) {
            throw LogicExecutionContractError.invalidRequest(
                "stimulus artifact is missing from the input set"
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case inputs
        case design
        case stimulus
        case seed
        case waveformFormat
        case artifactDirectory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(SchemaVersion.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicExecutionError.invalidArtifact(
                "unsupported simulation request schema version \(schemaVersion)"
            )
        }
        runID = try container.decode(String.self, forKey: .runID)
        inputs = try container.decode([ArtifactReference].self, forKey: .inputs)
        design = try container.decode(LogicDesignReference.self, forKey: .design)
        stimulus = try container.decodeIfPresent(ArtifactReference.self, forKey: .stimulus)
        seed = try container.decodeIfPresent(UInt64.self, forKey: .seed)
        waveformFormat = try container.decode(LogicWaveformFormat.self, forKey: .waveformFormat)
        artifactDirectory = try container.decodeIfPresent(String.self, forKey: .artifactDirectory)
    }
}
