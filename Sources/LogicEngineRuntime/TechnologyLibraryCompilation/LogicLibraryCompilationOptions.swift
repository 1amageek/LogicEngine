import CircuiteFoundation

public struct LogicLibraryCompilationOptions: Sendable {
    public let firstEntityID: DesignEntityID
    public let operatingConditionPolicies: [LogicOperatingConditionPolicy]
    internal let sourceStorageCredit: UInt64

    public init(firstEntityID: DesignEntityID,
                operatingConditionPolicies: [LogicOperatingConditionPolicy] = []) {
        self.firstEntityID = firstEntityID
        self.operatingConditionPolicies = operatingConditionPolicies; sourceStorageCredit = 0
    }

    internal init(firstEntityID: DesignEntityID,
                  operatingConditionPolicies: [LogicOperatingConditionPolicy], sourceStorageCredit: UInt64) {
        self.firstEntityID = firstEntityID
        self.operatingConditionPolicies = operatingConditionPolicies; self.sourceStorageCredit = sourceStorageCredit
    }
}
