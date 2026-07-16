import CircuiteFoundation
import Foundation

/// Canonical identity for a logic design artifact and its top module.
public struct LogicDesignArtifact: Sendable, Hashable, Codable {
    public let artifact: ArtifactReference
    public let topDesignName: String
    public let designRevision: ContentDigest?

    public init(
        artifact: ArtifactReference,
        topDesignName: String,
        designRevision: ContentDigest? = nil
    ) {
        self.artifact = artifact
        self.topDesignName = topDesignName
        self.designRevision = designRevision
    }
}
