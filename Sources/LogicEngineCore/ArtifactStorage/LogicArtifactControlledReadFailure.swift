import CircuiteFoundationFileSystem

/// Keeps original causes and the failed root-close admission alive across copies.
public struct LogicArtifactControlledReadFailure: Error, Sendable {
    public let primary: any Error
    public let cleanup: (any Error)?
    private let retention: any ArtifactSourceRetention
    private let metadata: any ArtifactSourceRetention

    internal init(primary: any Error, cleanup: (any Error)? = nil,
                  retention: any ArtifactSourceRetention, metadata: any ArtifactSourceRetention) {
        self.primary = primary
        self.cleanup = cleanup
        self.retention = retention
        self.metadata = metadata
    }
}
