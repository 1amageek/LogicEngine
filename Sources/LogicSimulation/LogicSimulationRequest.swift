import Foundation
import XcircuitePackage
import LogicIR
import LogicEngineCore

public struct LogicSimulationRequest: XcircuiteEngineRequest {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [XcircuiteFileReference]

    public var design: LogicDesignReference
    public var stimulus: XcircuiteFileReference?
    public var seed: UInt64?
    public var waveformFormat: LogicWaveformFormat
    public var artifactDirectory: String?

    public init(
        runID: String,
        inputs: [XcircuiteFileReference],
        design: LogicDesignReference,
        stimulus: XcircuiteFileReference? = nil,
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
        inputs = try container.decode([XcircuiteFileReference].self, forKey: .inputs)
        design = try container.decode(LogicDesignReference.self, forKey: .design)
        stimulus = try container.decodeIfPresent(XcircuiteFileReference.self, forKey: .stimulus)
        seed = try container.decodeIfPresent(UInt64.self, forKey: .seed)
        waveformFormat = try container.decodeIfPresent(LogicWaveformFormat.self, forKey: .waveformFormat) ?? .vcd
        artifactDirectory = try container.decodeIfPresent(String.self, forKey: .artifactDirectory)
    }
}
