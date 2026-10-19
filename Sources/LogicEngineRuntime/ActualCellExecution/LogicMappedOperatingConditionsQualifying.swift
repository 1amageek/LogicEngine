import LogicIR
import LogicKernelCore

public protocol LogicMappedOperatingConditionsQualifying: Sendable {
    func qualifyOperatingConditions(_ candidate: borrowing MappedGateDesign, context: inout LogicKernelContext)
        throws(LogicOperatingConditionError) -> LogicCheckedOperatingConditions
}
