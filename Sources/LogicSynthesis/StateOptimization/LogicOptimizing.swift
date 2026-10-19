import LogicIR
import LogicKernelCore

public protocol LogicOptimizing: Sendable {
    func optimize(_ design: borrowing BitLogicDesign, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicOptimizationCandidate
}
