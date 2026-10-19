import LogicEngineRuntime

public struct LogicEquivalenceCapabilities: Sendable, Hashable, Codable {
    public let implementation: String
    public let requestSchemaMajor: UInt16
    public let independentRUPChecking: Bool
    public let actualCellFunctions: Bool
    public let checkedArtifactReload: Bool

    public static let native = Self(implementation: "native-actual-cell-rup",
        requestSchemaMajor: LogicEquivalenceRequest.currentSchemaVersion.major,
        independentRUPChecking: true, actualCellFunctions: true, checkedArtifactReload: true)
}
