import CircuiteFoundation
import Foundation

/// An explicit immutable host read grant; artifact bytes cannot create one.
public struct LogicArtifactReadRoot: Sendable {
    public let rootID: ArtifactRootID
    public let directoryURL: URL
    internal let segments: [String]

    public init(rootID: ArtifactRootID, directoryURL: URL) throws {
        guard directoryURL.isFileURL else { throw LogicArtifactReadRootError.fileDirectoryRequired }
        guard rootID.rawValue != LogicArtifactBinding.workspaceRootIdentifier,
              rootID.rawValue != LogicArtifactBinding.outputRootIdentifier,
              rootID.rawValue != LogicArtifactBinding.localFileSystemRootIdentifier else {
            throw LogicArtifactReadRootError.reservedRootID(rootID)
        }
        self.rootID = rootID
        self.directoryURL = URL(fileURLWithPath: directoryURL.standardizedFileURL.path(percentEncoded: false), isDirectory: true)
        self.segments = self.directoryURL.path(percentEncoded: false).split(separator: "/").map(String.init)
    }
}
