import LogicKernelCore

public struct LogicCNFFormula: Sendable {
    public static let schemaVersion = 1
    internal final class Storage: Sendable {
        let variables: Int
        let clauses: [Range<Int>]
        let literals: [LogicSATLiteral]
        init(variables: Int, clauses: consuming [Range<Int>], literals: consuming [LogicSATLiteral]) {
            self.variables = variables; self.clauses = clauses; self.literals = literals
        }
    }
    internal let storage: Storage
    internal init(storage: Storage) { self.storage = storage }
    public var variableCount: Int { storage.variables }
    public var clauseCount: Int { storage.clauses.count }
    public var literalCount: Int { storage.literals.count }
    public borrowing func withClauses<Result, Failure: Error>(
        _ body: (borrowing Span<Range<Int>>, borrowing Span<LogicSATLiteral>) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        let owner = storage; let clauses = owner.clauses; let literals = owner.literals
        defer { withExtendedLifetime(owner) {} }
        return try body(clauses.span, literals.span)
    }
    internal borrowing func admit(context: inout LogicKernelContext) throws(LogicKernelError) {
        try context.checkpoint()
        try context.require(.cnfVariables, amount: UInt64(variableCount))
        try context.require(.cnfClauses, amount: UInt64(clauseCount))
    }
    internal borrowing func sameContent(as other: borrowing Self, context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        guard variableCount == other.variableCount, clauseCount == other.clauseCount, literalCount == other.literalCount else { return false }
        if storage === other.storage { return true }
        return try withClauses { clauses, literals throws(LogicKernelError) in
            try other.withClauses { otherClauses, otherLiterals throws(LogicKernelError) in
                for index in clauses.indices {
                    try context.charge(.workUnits)
                    if clauses[index] != otherClauses[index] { return false }
                }
                for index in literals.indices {
                    try context.charge(.workUnits)
                    if literals[index] != otherLiterals[index] { return false }
                }
                return true
            }
        }
    }
}
