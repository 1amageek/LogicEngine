import LogicKernelCore

internal struct TseitinBuilder: ~Copyable {
    private var variables = 0
    private var clauses = ProofBuffer<Range<Int>>()
    private var literals = ProofBuffer<LogicSATLiteral>()
    mutating func fresh(context: inout LogicKernelContext) throws(LogicKernelError) -> LogicSATLiteral {
        try context.charge(.workUnits)
        let next = variables.addingReportingOverflow(1)
        guard !next.overflow else { throw .invalidInput("Tseitin variable count overflows") }
        try context.require(.cnfVariables, amount: UInt64(next.partialValue))
        variables = next.partialValue
        return .init(variable: .init(validated: variables))
    }
    mutating func clause(_ a: LogicSATLiteral, _ b: LogicSATLiteral? = nil, _ c: LogicSATLiteral? = nil,
                         context: inout LogicKernelContext) throws(LogicKernelError) {
        let next = clauses.count.addingReportingOverflow(1)
        guard !next.overflow else { throw .invalidInput("Tseitin clause count overflows") }
        try context.require(.cnfClauses, amount: UInt64(next.partialValue))
        let start = literals.count
        try literals.append(a, context: &context)
        if let b { try literals.append(b, context: &context) }
        if let c { try literals.append(c, context: &context) }
        try clauses.append(start..<literals.count, context: &context)
    }
    mutating func equate(_ y: LogicSATLiteral, _ x: LogicSATLiteral, context: inout LogicKernelContext) throws(LogicKernelError) {
        try clause(y.negated, x, context: &context); try clause(y, x.negated, context: &context)
    }
    mutating func constant(_ value: Bool, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicSATLiteral {
        let y = try fresh(context: &context); try clause(value ? y : y.negated, context: &context); return y
    }
    mutating func and(_ a: LogicSATLiteral, _ b: LogicSATLiteral, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicSATLiteral {
        let y = try fresh(context: &context)
        try clause(a.negated, b.negated, y, context: &context)
        try clause(a, y.negated, context: &context); try clause(b, y.negated, context: &context)
        return y
    }
    mutating func or(_ a: LogicSATLiteral, _ b: LogicSATLiteral, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicSATLiteral {
        let y = try fresh(context: &context)
        try clause(a.negated, y, context: &context); try clause(b.negated, y, context: &context)
        try clause(a, b, y.negated, context: &context); return y
    }
    mutating func xor(_ a: LogicSATLiteral, _ b: LogicSATLiteral, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicSATLiteral {
        let y = try fresh(context: &context)
        try clause(a, b, y.negated, context: &context); try clause(a.negated, b.negated, y.negated, context: &context)
        try clause(a, b.negated, y, context: &context); try clause(a.negated, b, y, context: &context); return y
    }
    mutating func select(_ s: LogicSATLiteral, _ t: LogicSATLiteral, _ f: LogicSATLiteral, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicSATLiteral {
        let y = try fresh(context: &context)
        try clause(s.negated, t.negated, y, context: &context); try clause(s.negated, t, y.negated, context: &context)
        try clause(s, f.negated, y, context: &context); try clause(s, f, y.negated, context: &context); return y
    }
    borrowing func finish(context: inout LogicKernelContext) throws(LogicKernelError) -> LogicCNFFormula {
        var builder = try LogicCNFBuilder(variableCount: variables, clauseCapacity: clauses.count, literalCapacity: literals.count, context: &context)
        for index in clauses.indices {
            try literals.withSlice(clauses[index]) { values throws(LogicKernelError) in try builder.appendClause(values, context: &context) }
        }
        return try builder.finish(context: &context)
    }
    mutating func release(context: inout LogicKernelContext) throws(LogicKernelError) {
        try clauses.release(context: &context); try literals.release(context: &context)
    }
}
