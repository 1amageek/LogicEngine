import CircuiteFoundation
import TimingCore

/// One exact candidate instance/scenario, including source-checked unconditional cells.
public struct LogicResolvedOperatingCondition: Sendable, Hashable, Codable {
    public let instanceID: DesignEntityID
    public let interchangeName: String
    public let cellID: DesignEntityID
    public let cellName: String
    public let library: ArtifactReference
    public let cornerID: String?
    /// Nil requires a source-checked cell with no PG declarations or power-down programs.
    public let policyIndex: Int?
    public let normalPower: LibertyNormalPowerReceipt
}
