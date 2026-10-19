import LogicKernelCore

public struct CheckedLogicProof: Sendable {
    private let formula: LogicCNFFormula
    public let certificate: LogicRUPCertificate
    private init(formula: LogicCNFFormula, certificate: LogicRUPCertificate) { self.formula = formula; self.certificate = certificate }
    public borrowing func requireBinding(to formula: borrowing LogicCNFFormula) throws(LogicKernelError) {
        guard self.formula.storage === formula.storage else { throw .invalidInput("Checked proof belongs to another formula owner") }
    }
    internal static func independentlyCheck(_ formula: borrowing LogicCNFFormula, certificate: borrowing LogicRUPCertificate,
                                           context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        try formula.admit(context: &context); try certificate.admit(context: &context)
        guard try formula.sameContent(as: certificate.formula, context: &context) else { throw .invalidInput("RUP certificate CNF binding does not match") }
        let count = formula.variableCount.addingReportingOverflow(1)
        guard !count.overflow else { throw .invalidInput("RUP assignment count overflows") }
        let receipt = try context.reserveStorage(byteCount: UInt64(count.partialValue) + UInt64(MemoryLayout<[Int8]>.stride))
        do throws(LogicKernelError) {
            var values = [Int8](repeating: -1, count: count.partialValue)
            try formula.withClauses { original, originalLiterals throws(LogicKernelError) in
                try certificate.withAdditions { additions, addedLiterals throws(LogicKernelError) in
                    guard !additions.isEmpty, additions[additions.count - 1].isEmpty else { throw .invalidModel("RUP certificate is not a contradiction proof") }
                    for step in additions.indices {
                        try context.charge(.workUnits)
                        for index in values.indices { try context.charge(.workUnits); values[index] = -1 }
                        var conflict = false
                        for index in additions[step] {
                            try context.charge(.workUnits)
                            let literal = addedLiterals[index]; let variable = literal.variable.rawValue
                            let assumed: Int8 = literal.isPositive ? 0 : 1
                            if values[variable] >= 0 && values[variable] != assumed { conflict = true; break }
                            values[variable] = assumed
                        }
                        var changed = true
                        while !conflict && changed {
                            changed = false
                            for index in original.indices {
                                if try propagate(original[index], literals: originalLiterals, values: &values, changed: &changed, context: &context) { conflict = true; break }
                            }
                            if conflict { break }
                            for index in 0..<step {
                                if try propagate(additions[index], literals: addedLiterals, values: &values, changed: &changed, context: &context) { conflict = true; break }
                            }
                        }
                        guard conflict else { throw .invalidModel("RUP addition does not follow by unit propagation") }
                    }
                }
            }
        } catch { try context.releaseStorage(receipt); throw error }
        try context.releaseStorage(receipt)
        try context.checkpoint()
        return .init(formula: copy formula, certificate: copy certificate)
    }
    private static func propagate(_ range: Range<Int>, literals: borrowing Span<LogicSATLiteral>, values: inout [Int8],
                                  changed: inout Bool, context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        try context.charge(.workUnits)
        var unassigned = 0; var unit: LogicSATLiteral?
        for index in range {
            try context.charge(.workUnits)
            let literal = literals[index]; let value = values[literal.variable.rawValue]
            if value >= 0 && (value == 1) == literal.isPositive { return false }
            if value < 0 { unassigned += 1; unit = literal }
        }
        if unassigned == 0 { return true }
        if unassigned == 1, let unit {
            values[unit.variable.rawValue] = unit.isPositive ? 1 : 0; changed = true
        }
        return false
    }
}
