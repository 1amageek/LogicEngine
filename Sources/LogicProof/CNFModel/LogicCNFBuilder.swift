import LogicKernelCore

public struct LogicCNFBuilder: ~Copyable {
    internal enum Budget { case formula, proof }
    private let budget: Budget
    private let variables: Int
    private let clauseCapacity: Int
    private let literalCapacity: Int
    private var clauses: [Range<Int>]
    private var literals: [LogicSATLiteral]
    public init(variableCount: Int, clauseCapacity: Int, literalCapacity: Int, context: inout LogicKernelContext) throws(LogicKernelError) {
        try self.init(variableCount: variableCount, clauseCapacity: clauseCapacity, literalCapacity: literalCapacity, budget: .formula, context: &context)
    }
    internal init(variableCount: Int, clauseCapacity: Int, literalCapacity: Int, budget: Budget, context: inout LogicKernelContext) throws(LogicKernelError) {
        guard variableCount >= 0, clauseCapacity >= 0, literalCapacity >= 0 else { throw .invalidInput("CNF counts and capacities must be nonnegative") }
        if case .formula = budget {
            try context.charge(.cnfVariables, amount: UInt64(variableCount))
            try context.require(.cnfClauses, amount: UInt64(clauseCapacity))
        } else {
            let count = UInt64(clauseCapacity).addingReportingOverflow(UInt64(literalCapacity))
            let payload = count.partialValue.multipliedReportingOverflow(by: 8)
            let total = payload.partialValue.addingReportingOverflow(16)
            guard !count.overflow, !payload.overflow, !total.overflow else { throw .invalidInput("RUP capacity payload overflows") }
            try context.require(.proofBytes, amount: total.partialValue)
            try context.charge(.proofBytes, amount: 16)
        }
        let ranges = UInt64(clauseCapacity).multipliedReportingOverflow(by: UInt64(MemoryLayout<Range<Int>>.stride))
        let values = UInt64(literalCapacity).multipliedReportingOverflow(by: UInt64(MemoryLayout<LogicSATLiteral>.stride))
        let combined = ranges.partialValue.addingReportingOverflow(values.partialValue)
        let total = combined.partialValue.addingReportingOverflow(UInt64(MemoryLayout<Self>.stride + MemoryLayout<(Int, [Range<Int>], [LogicSATLiteral])>.stride))
        guard !ranges.overflow, !values.overflow, !combined.overflow, !total.overflow else { throw .invalidInput("CNF storage capacity overflows") }
        _ = try context.reserveStorage(byteCount: total.partialValue)
        self.budget = budget
        variables = variableCount; self.clauseCapacity = clauseCapacity; self.literalCapacity = literalCapacity
        clauses = []; literals = []; clauses.reserveCapacity(clauseCapacity); literals.reserveCapacity(literalCapacity)
    }
    public mutating func appendClause(_ values: borrowing [LogicSATLiteral], context: inout LogicKernelContext) throws(LogicKernelError) {
        try appendClause(values.span, context: &context)
    }
    public mutating func appendClause(_ values: borrowing Span<LogicSATLiteral>, context: inout LogicKernelContext) throws(LogicKernelError) {
        guard clauses.count < clauseCapacity else { throw .invalidInput("CNF clause capacity exhausted") }
        let start = literals.count
        do throws(LogicKernelError) {
            for index in values.indices {
                try context.charge(.workUnits)
                let value = values[index]
                guard value.variable.rawValue <= variables else { throw .invalidModel("CNF literal references an undeclared variable") }
                var duplicate = false
                for previous in start..<literals.count {
                    try context.charge(.workUnits)
                    if literals[previous] == value { duplicate = true; break }
                }
                if duplicate { continue }
                guard literals.count < literalCapacity else { throw .invalidInput("CNF literal capacity exhausted") }
                literals.append(value)
            }
            switch budget {
            case .formula: try context.charge(.cnfClauses)
            case .proof:
                let payload = UInt64(literals.count - start).multipliedReportingOverflow(by: 8)
                let length = payload.partialValue.addingReportingOverflow(8)
                guard !payload.overflow, !length.overflow else { throw .invalidInput("RUP clause payload overflows") }
                try context.charge(.proofBytes, amount: length.partialValue)
            }
            clauses.append(start..<literals.count)
        } catch {
            literals.removeLast(literals.count - start)
            throw error
        }
    }
    public consuming func finish(context: inout LogicKernelContext) throws(LogicKernelError) -> LogicCNFFormula {
        try context.checkpoint()
        return .init(storage: .init(variables: variables, clauses: clauses, literals: literals))
    }
}
