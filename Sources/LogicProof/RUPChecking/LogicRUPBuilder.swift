import LogicKernelCore

public struct LogicRUPBuilder: ~Copyable {
    private let formula: LogicCNFFormula
    private var additions: LogicCNFBuilder
    private var terminated: Bool
    public init(formula: borrowing LogicCNFFormula, clauseCapacity: Int, literalCapacity: Int, context: inout LogicKernelContext) throws(LogicKernelError) {
        try formula.admit(context: &context)
        _ = try context.reserveStorage(byteCount: UInt64(MemoryLayout<(LogicCNFFormula, LogicCNFFormula)>.stride + MemoryLayout<Self>.stride))
        let buffer = try LogicCNFBuilder(variableCount: formula.variableCount, clauseCapacity: clauseCapacity, literalCapacity: literalCapacity, budget: .proof, context: &context)
        self.formula = copy formula; self.additions = consume buffer; terminated = false
    }
    public mutating func appendClause(_ literals: borrowing [LogicSATLiteral], context: inout LogicKernelContext) throws(LogicKernelError) {
        try appendClause(literals.span, context: &context)
    }
    public mutating func appendClause(_ literals: borrowing Span<LogicSATLiteral>, context: inout LogicKernelContext) throws(LogicKernelError) {
        guard !terminated else { throw .invalidInput("RUP certificate already terminates with the empty clause") }
        try additions.appendClause(literals, context: &context)
        terminated = literals.isEmpty
    }
    public consuming func finish(context: inout LogicKernelContext) throws(LogicKernelError) -> LogicRUPCertificate {
        guard terminated else { throw .invalidModel("RUP certificate lacks its final empty clause") }
        return .init(formula: formula, additions: try additions.finish(context: &context))
    }
}
