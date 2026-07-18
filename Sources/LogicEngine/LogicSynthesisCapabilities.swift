import LogicSynthesis

public struct LogicSynthesisCapabilities: Sendable, Hashable, Codable {
    public let implementation: String
    public let equivalenceRequired: Bool
    public let acceptanceState: LogicSynthesisAcceptanceState
    public let equivalenceRequestArtifact: Bool

    public init(
        implementation: String,
        equivalenceRequired: Bool,
        acceptanceState: LogicSynthesisAcceptanceState,
        equivalenceRequestArtifact: Bool
    ) {
        self.implementation = implementation
        self.equivalenceRequired = equivalenceRequired
        self.acceptanceState = acceptanceState
        self.equivalenceRequestArtifact = equivalenceRequestArtifact
    }

    public static let native = Self(
        implementation: "native-lowering-optimization-mapping",
        equivalenceRequired: true,
        acceptanceState: .pendingEquivalence,
        equivalenceRequestArtifact: true
    )
}
