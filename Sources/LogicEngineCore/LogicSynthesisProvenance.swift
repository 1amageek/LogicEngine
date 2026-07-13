import Foundation

public struct LogicSynthesisProvenance: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var inputDesignDigest: String
    public var outputDesignDigest: String
    public var libraryDigests: [String]
    public var pdkDigest: String
    public var constraintsDigest: String
    public var transformations: [LogicTransformationRecord]
    public var equivalenceRequired: Bool

    public init(
        schemaVersion: Int = LogicSynthesisProvenance.currentSchemaVersion,
        runID: String,
        inputDesignDigest: String,
        outputDesignDigest: String,
        libraryDigests: [String],
        pdkDigest: String,
        constraintsDigest: String,
        transformations: [LogicTransformationRecord],
        equivalenceRequired: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.inputDesignDigest = inputDesignDigest
        self.outputDesignDigest = outputDesignDigest
        self.libraryDigests = libraryDigests
        self.pdkDigest = pdkDigest
        self.constraintsDigest = constraintsDigest
        self.transformations = transformations
        self.equivalenceRequired = equivalenceRequired
    }
}
