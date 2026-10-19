import LogicKernelCore

public struct LogicRUPCertificate: Sendable {
    public static let schemaVersion = 1
    private final class Storage: Sendable {
        let formula: LogicCNFFormula
        let additions: LogicCNFFormula
        init(formula: LogicCNFFormula, additions: LogicCNFFormula) { self.formula = formula; self.additions = additions }
    }
    private let storage: Storage
    internal init(formula: LogicCNFFormula, additions: LogicCNFFormula) { storage = .init(formula: formula, additions: additions) }
    public var formula: LogicCNFFormula { storage.formula }
    public var additionCount: Int { storage.additions.clauseCount }
    public var literalCount: Int { storage.additions.literalCount }
    public borrowing func withAdditions<Result, Failure: Error>(
        _ body: (borrowing Span<Range<Int>>, borrowing Span<LogicSATLiteral>) throws(Failure) -> Result
    ) throws(Failure) -> Result { try storage.additions.withClauses(body) }
    internal borrowing func admit(context: inout LogicKernelContext) throws(LogicKernelError) {
        let count = UInt64(additionCount).addingReportingOverflow(UInt64(literalCount))
        let payload = count.partialValue.multipliedReportingOverflow(by: 8)
        let total = payload.partialValue.addingReportingOverflow(16)
        guard !count.overflow, !payload.overflow, !total.overflow else { throw .invalidModel("RUP certificate payload overflows") }
        try context.require(.proofBytes, amount: total.partialValue)
    }
}
