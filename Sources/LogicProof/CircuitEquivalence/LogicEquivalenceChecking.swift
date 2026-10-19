import LogicKernelCore

public protocol LogicEquivalenceChecking: Sendable {
    func check(_ problem: borrowing LogicEquivalenceProblem, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicEquivalenceVerdict
}
