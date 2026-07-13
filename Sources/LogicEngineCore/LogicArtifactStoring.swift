import Foundation
import XcircuitePackage

public protocol LogicArtifactStoring: Sendable {
    func read(_ reference: XcircuiteFileReference) throws -> Data

    func write(
        _ data: Data,
        fileName: String,
        outputDirectory: String?,
        runID: String,
        artifactID: String?,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat
    ) throws -> XcircuiteFileReference
}
