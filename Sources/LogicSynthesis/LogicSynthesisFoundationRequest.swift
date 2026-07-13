import CircuiteFoundation
import Foundation
import LogicEngineCore

/// Foundation-native inputs for deterministic logic synthesis and mapping.
public struct LogicSynthesisFoundationRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = SchemaVersion.v1

    public let schemaVersion: SchemaVersion
    public let runID: String
    public let inputs: [ArtifactReference]
    public let design: LogicFoundationDesignReference
    public let libraries: [LogicSynthesisFoundationLibraryReference]
    public let constraints: ArtifactReference
    public let constraintModeIDs: [String]
    public let pdkManifest: ArtifactReference
    public let processID: String
    public let pdkVersion: String
    public let pdkDigest: ContentDigest
    public let powerIntent: ArtifactReference?
    public let powerIntentDesignRevision: ContentDigest?
    public let artifactDirectory: String?

    public init(
        runID: String,
        design: LogicFoundationDesignReference,
        libraries: [LogicSynthesisFoundationLibraryReference],
        constraints: ArtifactReference,
        pdkManifest: ArtifactReference,
        processID: String,
        pdkVersion: String,
        pdkDigest: ContentDigest,
        constraintModeIDs: [String] = [],
        powerIntent: ArtifactReference? = nil,
        powerIntentDesignRevision: ContentDigest? = nil,
        inputs: [ArtifactReference] = [],
        artifactDirectory: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.design = design
        self.libraries = libraries
        self.constraints = constraints
        self.constraintModeIDs = constraintModeIDs
        self.pdkManifest = pdkManifest
        self.processID = processID
        self.pdkVersion = pdkVersion
        self.pdkDigest = pdkDigest
        self.powerIntent = powerIntent
        self.powerIntentDesignRevision = powerIntentDesignRevision
        self.artifactDirectory = artifactDirectory

        var allInputs: [ArtifactReference] = []
        for artifact in [design.artifact] where !allInputs.contains(artifact) {
            allInputs.append(artifact)
        }
        for artifact in libraries.map(\.artifact) + [constraints, pdkManifest] + inputs
            where !allInputs.contains(artifact) {
            allInputs.append(artifact)
        }
        if let powerIntent, !allInputs.contains(powerIntent) {
            allInputs.append(powerIntent)
        }
        self.inputs = allInputs
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicFoundationBoundaryError.invalidRequest(
                "unsupported synthesis request schema version \(schemaVersion)"
            )
        }
        guard !runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicFoundationBoundaryError.invalidRequest("run ID is empty")
        }
        guard !design.topDesignName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicFoundationBoundaryError.invalidRequest("top design name is empty")
        }
        guard !libraries.isEmpty else {
            throw LogicFoundationBoundaryError.invalidRequest(
                "at least one timing library is required"
            )
        }
        guard pdkDigest.algorithm == .sha256 else {
            throw LogicFoundationBoundaryError.invalidRequest("PDK digest must use SHA-256")
        }
        var requiredArtifacts = [design.artifact, constraints, pdkManifest]
            + libraries.map(\.artifact)
        if let powerIntent {
            requiredArtifacts.append(powerIntent)
        }
        guard requiredArtifacts.allSatisfy({ inputs.contains($0) }) else {
            throw LogicFoundationBoundaryError.invalidRequest(
                "one or more synthesis prerequisites are missing from the input set"
            )
        }
        guard !processID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicFoundationBoundaryError.invalidRequest("PDK process ID is empty")
        }
        guard !pdkVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicFoundationBoundaryError.invalidRequest("PDK version is empty")
        }
    }
}
