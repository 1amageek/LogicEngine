import CircuiteFoundation

public enum LogicArtifactReadRootError: Error, Sendable, Equatable {
    case fileDirectoryRequired
    case reservedRootID(ArtifactRootID)
    case duplicateRootID(ArtifactRootID)
}
