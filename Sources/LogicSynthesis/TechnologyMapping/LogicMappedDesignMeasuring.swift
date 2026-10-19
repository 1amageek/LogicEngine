import LogicIR
import LogicKernelCore

public protocol LogicMappedDesignMeasuring: Sendable {
    func measure(_ design: borrowing MappedGateDesign, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicMappingStatistics
}
