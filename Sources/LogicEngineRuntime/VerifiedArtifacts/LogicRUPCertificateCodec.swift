import Foundation
import LogicKernelCore
import LogicProof

public struct LogicRUPCertificateCodec: Sendable {
    public init() {}
    public func encode(_ certificate: borrowing LogicRUPCertificate) throws -> Data {
        let clauses = certificate.formula.withClauses { ranges, literals in
            ranges.indices.map { c in ranges[c].map { literals[$0].rawValue } }
        }
        let additions = certificate.withAdditions { ranges, literals in
            ranges.indices.map { c in ranges[c].map { literals[$0].rawValue } }
        }
        let record = Record(schemaVersion: 1, variables: certificate.formula.variableCount,
                            clauses: clauses, additions: additions)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(record)
    }
    public func decode(_ data: Data, context: inout LogicKernelContext) throws -> LogicRUPCertificate {
        try context.charge(.expansion, amount: UInt64(data.count))
        let record = try JSONDecoder().decode(Record.self, from: data)
        guard record.schemaVersion == 1 else { throw LogicKernelError.invalidInput("Unsupported RUP schema") }
        var formula = try LogicCNFBuilder(variableCount: record.variables, clauseCapacity: record.clauses.count,
                                         literalCapacity: count(record.clauses), context: &context)
        for clause in record.clauses { try formula.appendClause(try clause.map(LogicSATLiteral.init), context: &context) }
        let cnf = try formula.finish(context: &context)
        var proof = try LogicRUPBuilder(formula: cnf, clauseCapacity: record.additions.count,
                                       literalCapacity: count(record.additions), context: &context)
        for clause in record.additions { try proof.appendClause(try clause.map(LogicSATLiteral.init), context: &context) }
        return try proof.finish(context: &context)
    }
    private func count(_ clauses: [[Int]]) throws -> Int {
        var total = 0
        for clause in clauses {
            let sum = total.addingReportingOverflow(clause.count)
            guard !sum.overflow else { throw LogicKernelError.invalidInput("Certificate size overflows") }
            total = sum.partialValue
        }
        return total
    }
    private struct Record: Codable { let schemaVersion: Int; let variables: Int; let clauses: [[Int]]; let additions: [[Int]] }
}
