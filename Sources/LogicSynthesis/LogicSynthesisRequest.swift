import CircuiteFoundation
import Foundation
import LogicIR
import PowerIntent
import TimingCore
import PDKCore
import LogicEngineCore

public struct LogicSynthesisRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = SchemaVersion.v3

    public var schemaVersion: SchemaVersion
    public var runID: String
    public var inputs: [ArtifactReference]
    public var inputBindings: [LogicArtifactBinding]

    public var design: LogicDesignReference
    public var libraries: [TimingLibraryReference]
    public var constraints: LogicArtifactBinding
    public var pdk: PDKReference
    public var powerIntent: PowerIntentReference?
    public var powerIntentBinding: LogicArtifactBinding?
    public var artifactDirectory: String?

    public init(
        runID: String,
        inputBindings: [LogicArtifactBinding],
        design: LogicDesignReference,
        libraries: [TimingLibraryReference],
        constraints: LogicArtifactBinding,
        pdk: PDKReference,
        powerIntent: PowerIntentReference? = nil,
        powerIntentBinding: LogicArtifactBinding? = nil,
        artifactDirectory: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.inputBindings = inputBindings
        let prerequisites = inputBindings.map(\.reference)
            + libraries.map(\.artifact.reference)
            + [constraints.reference, pdk.manifest]
            + (powerIntent.map { [$0.artifact] } ?? [])
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
        self.powerIntentBinding = powerIntentBinding
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
        do {
            _ = try ContentDigest(algorithm: .sha256, hexadecimalValue: design.designDigest)
        } catch {
            throw LogicExecutionContractError.invalidRequest(
                "design must carry a valid SHA-256 digest"
            )
        }
        guard !libraries.isEmpty else {
            throw LogicExecutionContractError.invalidRequest(
                "at least one timing library is required"
            )
        }
        guard constraints.descriptor.kind == .constraint else {
            throw LogicExecutionContractError.invalidRequest(
                "synthesis constraints must use the constraint artifact kind"
            )
        }
        var requiredArtifacts = [design.artifact]
            + libraries.map(\.artifact.reference)
            + [constraints.reference, pdk.manifest]
        if let powerIntent {
            requiredArtifacts.append(powerIntent.artifact)
        }
        guard requiredArtifacts.allSatisfy(inputs.contains) else {
            throw LogicExecutionContractError.invalidRequest(
                "one or more synthesis prerequisites are missing from the input set"
            )
        }
        guard inputBindings.contains(where: { $0.reference == design.artifact }) else {
            throw LogicExecutionContractError.invalidRequest(
                "design materialization is missing from synthesis input bindings"
            )
        }
        if let powerIntent {
            guard powerIntentBinding?.reference == powerIntent.artifact else {
                throw LogicExecutionContractError.invalidRequest(
                    "power intent identity and materialization do not match"
                )
            }
        } else if powerIntentBinding != nil {
            throw LogicExecutionContractError.invalidRequest(
                "power intent materialization has no semantic reference"
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
        case inputBindings
        case design
        case libraries
        case constraints
        case pdk
        case powerIntent
        case powerIntentBinding
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
        inputBindings = try container.decode([LogicArtifactBinding].self, forKey: .inputBindings)
        design = try container.decode(LogicDesignReference.self, forKey: .design)
        libraries = try container.decode([TimingLibraryReference].self, forKey: .libraries)
        constraints = try container.decode(LogicArtifactBinding.self, forKey: .constraints)
        pdk = try container.decode(PDKReference.self, forKey: .pdk)
        powerIntent = try container.decodeIfPresent(PowerIntentReference.self, forKey: .powerIntent)
        powerIntentBinding = try container.decodeIfPresent(
            LogicArtifactBinding.self,
            forKey: .powerIntentBinding
        )
        artifactDirectory = try container.decodeIfPresent(String.self, forKey: .artifactDirectory)
    }
}
