import LogicDesignSerialization
import LogicIR
import LogicKernelCore

internal enum LogicReloadGraphComparison {
    static func bit(_ lhs: borrowing BitLogicDesign, _ rhs: borrowing BitLogicDesign,
                    context: inout LogicKernelContext) throws -> Bool {
        let left = try BitLogicDesignCodec().encodeControlled(lhs, context: &context)
        let right = try BitLogicDesignCodec().encodeControlled(rhs, context: &context)
        defer { withExtendedLifetime(left.retention) {}; withExtendedLifetime(right.retention) {} }
        try LogicReloadComparison.charge(UInt64(left.value.count), UInt64(right.value.count), context: &context)
        return left.value == right.value
    }
    static func mapped(_ lhs: borrowing MappedGateDesign, _ rhs: borrowing MappedGateDesign,
                       context: inout LogicKernelContext) throws -> Bool {
        let left = try MappedGateDesignCodec().encodeControlled(lhs, context: &context)
        let right = try MappedGateDesignCodec().encodeControlled(rhs, context: &context)
        defer { withExtendedLifetime(left.retention) {}; withExtendedLifetime(right.retention) {} }
        try LogicReloadComparison.charge(UInt64(left.value.count), UInt64(right.value.count), context: &context)
        return left.value == right.value
    }
}
