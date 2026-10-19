import CircuiteFoundation
import Foundation

public protocol LogicArtifactStoring: Sendable {
    func read(_ artifact: LogicArtifactBinding) throws -> Data

    func write(
        _ data: Data,
        fileName: String,
        outputDirectory: String?,
        runID: String,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> LogicArtifactBinding
}
