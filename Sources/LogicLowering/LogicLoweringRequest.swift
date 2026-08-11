import CircuiteFoundation
import Foundation
import LogicIR
import LogicEngineCore

public struct LogicLoweringRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = SchemaVersion.v2

    public var schemaVersion: SchemaVersion
    public var runID: String
    public var inputs: [ArtifactReference]
    public var inputBindings: [LogicArtifactBinding]
    public var design: LogicDesignReference
    public var artifactDirectory: String?

    public init(
        runID: String,
        inputBindings: [LogicArtifactBinding],
        design: LogicDesignReference,
        artifactDirectory: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        var uniqueBindings: [LogicArtifactBinding] = []
        for binding in inputBindings where !uniqueBindings.contains(where: { $0.reference == binding.reference }) {
            uniqueBindings.append(binding)
        }
        self.inputs = uniqueBindings.map(\.reference)
        self.inputBindings = uniqueBindings
        self.design = design
        self.artifactDirectory = artifactDirectory
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicExecutionContractError.invalidRequest(
                "unsupported lowering request schema version \(schemaVersion)"
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
        guard inputBindings.map(\.reference) == inputs else {
            throw LogicExecutionContractError.invalidRequest(
                "input bindings do not match the content-only input lineage"
            )
        }
    }
}
