import CircuiteFoundation
import Foundation
import LogicIR
import LogicEngineCore

public struct LogicSimulationRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [ArtifactReference]

    public var design: LogicFoundationDesignReference
    public var stimulus: ArtifactReference?
    public var seed: UInt64?
    public var waveformFormat: LogicWaveformFormat
    public var artifactDirectory: String?

    public init(
        runID: String,
        inputs: [ArtifactReference],
        design: LogicFoundationDesignReference,
        stimulus: ArtifactReference? = nil,
        seed: UInt64? = nil,
        waveformFormat: LogicWaveformFormat = .vcd,
        artifactDirectory: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.inputs = inputs
        self.design = design
        self.stimulus = stimulus
        self.seed = seed
        self.waveformFormat = waveformFormat
        self.artifactDirectory = artifactDirectory
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
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        runID = try container.decode(String.self, forKey: .runID)
        inputs = try container.decode([ArtifactReference].self, forKey: .inputs)
        design = try container.decode(LogicFoundationDesignReference.self, forKey: .design)
        stimulus = try container.decodeIfPresent(ArtifactReference.self, forKey: .stimulus)
        seed = try container.decodeIfPresent(UInt64.self, forKey: .seed)
        waveformFormat = try container.decodeIfPresent(LogicWaveformFormat.self, forKey: .waveformFormat) ?? .vcd
        artifactDirectory = try container.decodeIfPresent(String.self, forKey: .artifactDirectory)
    }
}
