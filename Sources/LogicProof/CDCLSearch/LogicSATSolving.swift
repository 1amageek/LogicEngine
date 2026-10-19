import LogicKernelCore

public protocol LogicSATSolving: Sendable {
    func solve(_ formula: borrowing LogicCNFFormula, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicSATOutcome
}
