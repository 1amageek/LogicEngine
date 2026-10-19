import LogicKernelCore

public struct LogicSATAssignment: Sendable {
    private final class Storage: Sendable {
        let values: [Int8]
        init(values: consuming [Int8]) { self.values = values }
    }
    private let formula: LogicCNFFormula
    private let storage: Storage
    internal static var storageByteCount: UInt64 { UInt64(MemoryLayout<[Int8]>.stride + MemoryLayout<Self>.stride) }
    internal init(formula: borrowing LogicCNFFormula, values: consuming [Int8]) {
        self.formula = copy formula; storage = .init(values: values)
    }
    public var variableCount: Int { formula.variableCount }
    public func value(of variable: LogicSATVariable) throws(LogicKernelError) -> Bool {
        guard variable.rawValue <= variableCount else { throw .invalidInput("Assignment variable is outside its formula") }
        return storage.values[variable.rawValue] == 1
    }
    public func requireBinding(to formula: borrowing LogicCNFFormula) throws(LogicKernelError) {
        guard self.formula.storage === formula.storage else { throw .invalidModel("SAT assignment belongs to a different formula owner") }
    }
    public func validate(_ formula: borrowing LogicCNFFormula, context: inout LogicKernelContext) throws(LogicKernelError) {
        try requireBinding(to: formula)
        try formula.withClauses { clauses, literals throws(LogicKernelError) in
            for clause in clauses.indices {
                var satisfied = false
                for position in clauses[clause] {
                    try context.charge(.workUnits)
                    let literal = literals[position]
                    if (storage.values[literal.variable.rawValue] == 1) == literal.isPositive { satisfied = true; break }
                }
                guard satisfied else { throw .invalidModel("SAT assignment does not satisfy the original CNF") }
            }
        }
    }
}
