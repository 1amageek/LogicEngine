import TimingCore

/// Transport only; replay reconstructs source-checked owners and complete instance coverage.
public struct LogicOperatingConditionReceipt: Sendable, Hashable, Codable {
    public let policies: [LogicOperatingConditionPolicy]
    public let policyOutcomes: [LibertyNormalPowerReceipt]
    public let records: [LogicResolvedOperatingCondition]
    public let unusedPolicyIndices: [Int]
}
