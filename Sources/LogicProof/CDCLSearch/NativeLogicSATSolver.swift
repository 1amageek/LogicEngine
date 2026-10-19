import LogicKernelCore

public struct NativeLogicSATSolver: LogicSATSolving {
    public init() {}
    public func solve(_ formula: borrowing LogicCNFFormula, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicSATOutcome {
        try formula.admit(context: &context)
        var workspace = try CDCLWorkspace(variableCount: formula.variableCount, context: &context)
        do throws(LogicKernelError) {
            let outcome = try workspace.solve(formula, context: &context)
            try workspace.release(context: &context)
            return outcome
        } catch {
            try workspace.release(context: &context)
            throw error
        }
    }
}
