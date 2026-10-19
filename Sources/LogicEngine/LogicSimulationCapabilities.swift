import LogicEngineRuntime

public struct LogicSimulationCapabilities: Sendable, Hashable, Codable {
    public let implementation: String
    public let requestSchemaMajor: UInt16
    public let fourState: Bool
    public let actualCellFunctions: Bool
    public let arbitraryWidth: Bool
    public let division: Bool
    public let modulo: Bool
    public let levelSensitiveLatch: Bool
    public let negativeEdgeSequential: Bool

    public static let native = Self(implementation: "native-four-state", requestSchemaMajor: LogicSimulationRequest.currentSchemaVersion.major,
        fourState: true, actualCellFunctions: true, arbitraryWidth: true, division: false,
        modulo: false, levelSensitiveLatch: true, negativeEdgeSequential: true)
}
