import CircuiteFoundationFileSystem

/// Keep this anchor alive with every copy of the returned Data.
public final class LogicArtifactReadRetention: Sendable {
    private let reservation: any ArtifactSourceRetention

    internal init(reservation: any ArtifactSourceRetention) {
        self.reservation = reservation
    }
}
