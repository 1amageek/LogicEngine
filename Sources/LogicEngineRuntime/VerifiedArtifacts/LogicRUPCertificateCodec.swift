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
    public func encodeControlled(_ certificate: borrowing LogicRUPCertificate,
        context: inout LogicKernelContext, resources: LogicReloadResources) throws
        -> (value: Data, retention: LogicKernelRetention) {
        try context.requireAccounting(expected: resources)
        var count = 0
        func add(_ amount: Int) throws(LogicKernelError) {
            let next = count.addingReportingOverflow(amount)
            guard amount >= 0, !next.overflow else { throw .invalidInput("Certificate output capacity overflows") }
            count = next.partialValue
        }
        func integerWidth(_ value: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
            var magnitude = value.magnitude
            var width = value < 0 ? 1 : 0
            repeat {
                try context.charge(.workUnits)
                width += 1; magnitude /= 10
            } while magnitude != 0
            return width
        }
        // Fixed schema plus actual decimal widths determine the exact output, before Data growth.
        try add("{\"additions\":".utf8.count)
        try certificate.withAdditions { ranges, literals in
            try add(2)
            for index in ranges.indices {
                try context.charge(.workUnits)
                if index > 0 { try add(1) }; try add(2)
                for offset in ranges[index] {
                    if offset > ranges[index].lowerBound { try add(1) }
                    try add(integerWidth(literals[offset].rawValue, context: &context))
                }
            }
        }
        try add(",\"clauses\":".utf8.count)
        try certificate.formula.withClauses { ranges, literals in
            try add(2)
            for index in ranges.indices {
                try context.charge(.workUnits)
                if index > 0 { try add(1) }; try add(2)
                for offset in ranges[index] {
                    if offset > ranges[index].lowerBound { try add(1) }
                    try add(integerWidth(literals[offset].rawValue, context: &context))
                }
            }
        }
        try add(",\"schemaVersion\":1,\"variables\":".utf8.count)
        try add(integerWidth(certificate.formula.variableCount, context: &context)); try add(1)
        let scope = try context.beginRetentionScope()
        let retention: LogicKernelRetention
        let result: Data
        do {
            _ = try context.reserveStorage(byteCount: UInt64(count))
            // A host Int is at most 64 bits in this profile: signed decimal needs at most 20 bytes.
            guard Int.bitWidth <= 64 else { throw LogicKernelError.unsupported("Unsupported host integer width") }
            let scratch = try context.reserveStorage(byteCount: 20)
            do {
                var data = Data(); data.reserveCapacity(count)
                func text(_ value: String, context: inout LogicKernelContext) throws {
                    try context.charge(.workUnits, amount: UInt64(value.utf8.count))
                    data.append(contentsOf: value.utf8)
                }
                try text("{\"additions\":[", context: &context)
                try certificate.withAdditions { ranges, literals in
                    for index in ranges.indices {
                        if index > 0 { try text(",", context: &context) }
                        try text("[", context: &context)
                        for offset in ranges[index] {
                            if offset > ranges[index].lowerBound { try text(",", context: &context) }
                            try context.charge(.workUnits)
                            try text(String(literals[offset].rawValue), context: &context)
                        }
                        try text("]", context: &context)
                    }
                }
                try text("],\"clauses\":[", context: &context)
                try certificate.formula.withClauses { ranges, literals in
                    for index in ranges.indices {
                        if index > 0 { try text(",", context: &context) }
                        try text("[", context: &context)
                        for offset in ranges[index] {
                            if offset > ranges[index].lowerBound { try text(",", context: &context) }
                            try context.charge(.workUnits)
                            try text(String(literals[offset].rawValue), context: &context)
                        }
                        try text("]", context: &context)
                    }
                }
                try text("],\"schemaVersion\":1,\"variables\":", context: &context)
                try text(String(certificate.formula.variableCount), context: &context)
                try text("}", context: &context)
                guard data.count == count else { throw LogicKernelError.invalidInput("Certificate output sizing mismatch") }
                result = data
            } catch {
                do { try context.releaseStorage(scratch) }
                catch let cleanup { throw LogicControlledReloadFailure(primary: error, secondary: cleanup) }
                throw error
            }
            try context.releaseStorage(scratch)
            try resources.checkCaller()
            retention = try context.finishRetentionScope(scope)
        } catch {
            throw LogicReloadKernelPhase.failure(error, scope: scope, context: &context, resources: resources)
        }
        try resources.checkCaller()
        return (result, retention)
    }

    public func decodeControlled(_ data: Data, limits: LogicRuntimeLimits,
        context: inout LogicKernelContext, resources: LogicReloadResources) throws
        -> (value: LogicRUPCertificate, retention: LogicKernelRetention) {
        try context.requireAccounting(expected: resources)
        try context.charge(.expansion, amount: UInt64(data.count))
        let document = try LogicReloadDocumentDecoding.decode(Record.self, data: data, limits: limits,
            context: &context, resources: resources, validate: { _ in })
        defer { withExtendedLifetime(document) {} }
        let record = document.value
        guard record.schemaVersion == 1 else { throw LogicKernelError.invalidInput("Unsupported RUP schema") }
        let scope = try context.beginRetentionScope()
        let value: LogicRUPCertificate
        let retention: LogicKernelRetention
        do {
            var formula = try LogicCNFBuilder(variableCount: record.variables, clauseCapacity: record.clauses.count,
                literalCapacity: controlledCount(record.clauses, context: &context), context: &context)
            for clause in record.clauses {
                try withLiterals(clause, context: &context) { values, context in
                    try formula.appendClause(values, context: &context)
                }
            }
            let cnf = try formula.finish(context: &context)
            var proof = try LogicRUPBuilder(formula: cnf, clauseCapacity: record.additions.count,
                literalCapacity: controlledCount(record.additions, context: &context), context: &context)
            for clause in record.additions {
                try withLiterals(clause, context: &context) { values, context in
                    try proof.appendClause(values, context: &context)
                }
            }
            value = try proof.finish(context: &context)
            try resources.checkCaller()
            retention = try context.finishRetentionScope(scope)
        } catch {
            throw LogicReloadKernelPhase.failure(error, scope: scope, context: &context, resources: resources)
        }
        try resources.checkCaller()
        return (value, retention)
    }

    private func controlledCount(_ clauses: [[Int]], context: inout LogicKernelContext)
        throws(LogicKernelError) -> Int {
        var total = 0
        for clause in clauses {
            try context.charge(.workUnits)
            let sum = total.addingReportingOverflow(clause.count)
            guard !sum.overflow else { throw .invalidInput("Certificate size overflows") }
            total = sum.partialValue
        }
        return total
    }

    private func withLiterals(_ raw: [Int], context: inout LogicKernelContext,
        append: (borrowing Span<LogicSATLiteral>, inout LogicKernelContext) throws -> Void) throws {
        let bytes = UInt64(raw.count).multipliedReportingOverflow(by: UInt64(MemoryLayout<LogicSATLiteral>.stride))
        guard !bytes.overflow else { throw LogicKernelError.invalidInput("Certificate conversion overflows") }
        let reservation = try context.reserveStorage(byteCount: bytes.partialValue)
        do {
            var values: [LogicSATLiteral] = []
            values.reserveCapacity(raw.count)
            for value in raw {
                try context.charge(.workUnits)
                values.append(try LogicSATLiteral(value))
            }
            try append(values.span, &context)
        } catch {
            do { try context.releaseStorage(reservation) }
            catch let cleanup { throw LogicControlledReloadFailure(primary: error, secondary: cleanup) }
            throw error
        }
        try context.releaseStorage(reservation)
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
    private struct Record: Codable, Sendable { let schemaVersion: Int; let variables: Int; let clauses: [[Int]]; let additions: [[Int]] }
}
