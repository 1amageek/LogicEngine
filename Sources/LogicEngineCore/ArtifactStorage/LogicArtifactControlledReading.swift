import CircuiteFoundation
import CircuiteFoundationFileSystem
import Foundation

public protocol LogicArtifactControlledReading: Sendable {
    func readControlled(
        _ artifact: LogicArtifactBinding,
        budget: ArtifactAccessBudget,
        control: any ArtifactSourceControl
    ) async throws -> (value: Data, retention: LogicArtifactReadRetention)
}
