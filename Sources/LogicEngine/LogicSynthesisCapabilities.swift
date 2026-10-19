import LogicEngineRuntime

public struct LogicSynthesisCapabilities: Sendable, Hashable, Codable {
    public let implementation: String
    public let equivalenceRequired: Bool
    public let actualCellMapping: Bool
    public let independentRUPChecking: Bool
    public let checkedArtifactReload: Bool
    public let synthesisRequestMajorVersion: UInt16

    public static let native = Self(implementation: "native-actual-cell-synthesis-v1", equivalenceRequired: true,
        actualCellMapping: true, independentRUPChecking: true, checkedArtifactReload: true,
        synthesisRequestMajorVersion: LogicSynthesisRequest.currentSchemaVersion.major)
}
