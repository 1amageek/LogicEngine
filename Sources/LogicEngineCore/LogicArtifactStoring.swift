import CircuiteFoundation
import Foundation

public protocol LogicArtifactStoring: Sendable {
    func read(_ reference: ArtifactReference) throws -> Data

    func write(
        _ data: Data,
        fileName: String,
        outputDirectory: String?,
        runID: String,
        artifactID: String?,
        kind: ArtifactKind,
        format: ArtifactFormat
    ) throws -> ArtifactReference
}
