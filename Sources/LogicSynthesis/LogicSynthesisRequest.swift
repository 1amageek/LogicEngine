import CircuiteFoundation
import Foundation
import LogicIR
import PowerIntent
import TimingCore
import PDKCore
import LogicEngineCore

public struct LogicSynthesisRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = SchemaVersion.v1

    public var schemaVersion: SchemaVersion
    public var runID: String
    public var inputs: [ArtifactReference]

    public var design: LogicDesignArtifact
    public var libraries: [TimingLibraryReference]
    public var constraints: ArtifactReference
    public var pdk: PDKReference
    public var powerIntent: PowerIntentReference?
    public var artifactDirectory: String?

    public init(
        runID: String,
        inputs: [ArtifactReference] = [],
        design: LogicDesignArtifact,
        libraries: [TimingLibraryReference],
        constraints: ArtifactReference,
        pdk: PDKReference,
        powerIntent: PowerIntentReference? = nil,
        artifactDirectory: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        let prerequisites = [design.artifact]
            + libraries.map(\.artifact)
            + [constraints, pdk.manifest]
            + (powerIntent.map { [$0.artifact] } ?? [])
            + inputs
        var allInputs: [ArtifactReference] = []
        for artifact in prerequisites where !allInputs.contains(artifact) {
            allInputs.append(artifact)
        }
        self.inputs = allInputs
        self.design = design
        self.libraries = libraries
        self.constraints = constraints
        self.pdk = pdk
        self.powerIntent = powerIntent
        self.artifactDirectory = artifactDirectory
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicExecutionContractError.invalidRequest(
                "unsupported synthesis request schema version \(schemaVersion)"
            )
        }
        guard !runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicExecutionContractError.invalidRequest("run ID is empty")
        }
        guard !design.topDesignName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicExecutionContractError.invalidRequest("top design name is empty")
        }
        guard !libraries.isEmpty else {
            throw LogicExecutionContractError.invalidRequest(
                "at least one timing library is required"
            )
        }
        var requiredArtifacts = [design.artifact]
            + libraries.map(\.artifact)
            + [constraints, pdk.manifest]
        if let powerIntent {
            requiredArtifacts.append(powerIntent.artifact)
        }
        guard requiredArtifacts.allSatisfy(inputs.contains) else {
            throw LogicExecutionContractError.invalidRequest(
                "one or more synthesis prerequisites are missing from the input set"
            )
        }
        do {
            try pdk.validate()
        } catch {
            throw LogicExecutionContractError.invalidRequest(
                "PDK reference is invalid: \(error.localizedDescription)"
            )
        }
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
        schemaVersion = try container.decode(SchemaVersion.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicExecutionError.invalidArtifact(
                "unsupported synthesis request schema version \(schemaVersion)"
            )
        }
        runID = try container.decode(String.self, forKey: .runID)
        inputs = try container.decode([ArtifactReference].self, forKey: .inputs)
        design = try container.decode(LogicDesignArtifact.self, forKey: .design)
        libraries = try container.decode([TimingLibraryReference].self, forKey: .libraries)
        constraints = try container.decode(ArtifactReference.self, forKey: .constraints)
        pdk = try container.decode(PDKReference.self, forKey: .pdk)
        powerIntent = try container.decodeIfPresent(PowerIntentReference.self, forKey: .powerIntent)
        artifactDirectory = try container.decodeIfPresent(String.self, forKey: .artifactDirectory)
    }
}
