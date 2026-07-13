import CircuiteFoundation
import Foundation

/// Foundation-native timing-library input used by logic synthesis.
public struct LogicSynthesisFoundationLibraryReference: Sendable, Hashable, Codable {
    public let artifact: ArtifactReference
    public let cornerIDs: [String]

    public init(artifact: ArtifactReference, cornerIDs: [String] = []) {
        self.artifact = artifact
        self.cornerIDs = cornerIDs
    }
}
