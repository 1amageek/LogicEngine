import CircuiteFoundation
import Foundation
import LogicIR
import PowerIntent
import TimingCore
import PDKCore
import LogicEngineCore
import CircuiteFoundation

public struct LogicSynthesisRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [ArtifactReference]

    public var design: LogicFoundationDesignReference
    public var libraries: [TimingLibraryReference]
    public var constraints: TimingConstraintReference
    public var pdk: PDKReference
    public var powerIntent: PowerIntentReference?
    public var artifactDirectory: String?

    public init(
        runID: String,
        inputs: [ArtifactReference],
        design: LogicFoundationDesignReference,
        libraries: [TimingLibraryReference],
        constraints: TimingConstraintReference,
        pdk: PDKReference,
        powerIntent: PowerIntentReference? = nil,
        artifactDirectory: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.inputs = inputs
        self.design = design
        self.libraries = libraries
        self.constraints = constraints
        self.pdk = pdk
        self.powerIntent = powerIntent
        self.artifactDirectory = artifactDirectory
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case runID
        case inputs
        case design
        case libraries
        case constraints
        case pdk
        case powerIntent
        case artifactDirectory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        runID = try container.decode(String.self, forKey: .runID)
        inputs = try container.decode([ArtifactReference].self, forKey: .inputs)
        design = try container.decode(LogicFoundationDesignReference.self, forKey: .design)
        libraries = try container.decode([TimingLibraryReference].self, forKey: .libraries)
        constraints = try container.decode(TimingConstraintReference.self, forKey: .constraints)
        pdk = try container.decode(PDKReference.self, forKey: .pdk)
        powerIntent = try container.decodeIfPresent(PowerIntentReference.self, forKey: .powerIntent)
        artifactDirectory = try container.decodeIfPresent(String.self, forKey: .artifactDirectory)
    }
}
