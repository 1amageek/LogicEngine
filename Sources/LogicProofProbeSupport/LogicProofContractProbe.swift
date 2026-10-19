import LogicKernelCore
import LogicProof

public enum LogicProofContractProbe {
    public struct Control: LogicRunControlling {
        public init() {}
        public func checkpoint() throws(LogicKernelError) {}
    }
    public static func context(limit: UInt64 = 100_000_000, control: any LogicRunControlling = Control()) throws(LogicKernelError) -> LogicKernelContext {
        var maximums: [LogicResource: UInt64] = [:]
        for resource in LogicResource.allCases { maximums[resource] = limit }
        return .init(limits: try .init(maximums: maximums), control: control)
    }
    public static func formula(_ rows: [[Int]], variables: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicCNFFormula {
        var count = 0
        for row in rows {
            let next = count.addingReportingOverflow(row.count)
            guard !next.overflow else { throw .invalidInput("Proof fixture literal count overflows") }; count = next.partialValue
        }
        var builder = try LogicCNFBuilder(variableCount: variables, clauseCapacity: rows.count, literalCapacity: count, context: &context)
        for row in rows {
            _ = try context.reserveStorage(byteCount: UInt64(row.count) * UInt64(MemoryLayout<LogicSATLiteral>.stride))
            var literals: [LogicSATLiteral] = []; literals.reserveCapacity(row.count)
            for raw in row { literals.append(try .init(raw)) }
            try builder.appendClause(literals, context: &context)
        }
        return try builder.finish(context: &context)
    }
    public static func certificate(_ rows: [[Int]], formula: borrowing LogicCNFFormula, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicRUPCertificate {
        var count = 0
        for row in rows {
            let next = count.addingReportingOverflow(row.count)
            guard !next.overflow else { throw .invalidInput("Proof fixture step count overflows") }; count = next.partialValue
        }
        var builder = try LogicRUPBuilder(formula: formula, clauseCapacity: rows.count, literalCapacity: count, context: &context)
        for row in rows {
            _ = try context.reserveStorage(byteCount: UInt64(row.count) * UInt64(MemoryLayout<LogicSATLiteral>.stride))
            var literals: [LogicSATLiteral] = []; literals.reserveCapacity(row.count)
            for raw in row { literals.append(try .init(raw)) }
            try builder.appendClause(literals, context: &context)
        }
        return try builder.finish(context: &context)
    }
    public static func exercise() throws(LogicKernelError) {
        var run = try context()
        let checker: any LogicProofChecking = NativeLogicRUPChecker()
        for (clauses, variables, steps) in [([[1],[-1]],1,[[]]), ([[1,2],[1,-2],[-1,2],[-1,-2]],2,[[1],[]]), ([[]],0,[[]])] {
            let formula = try Self.formula(clauses, variables: variables, context: &run)
            let certificate = try Self.certificate(steps, formula: formula, context: &run)
            let checked = try checker.check(formula, certificate: certificate, context: &run)
            try checked.requireBinding(to: formula)
        }
        let satisfiable = try formula([[1,2]], variables: 2, context: &run)
        let forged = try certificate([[1],[]], formula: satisfiable, context: &run)
        var refused = false
        do throws(LogicKernelError) { _ = try checker.check(satisfiable, certificate: forged, context: &run) }
        catch {
            guard case .invalidModel("RUP addition does not follow by unit propagation") = error else { throw error }
            refused = true
        }
        guard refused else { throw .invalidModel("Independent checker accepted a forged proof") }
        try exerciseSearch()
        try LogicEquivalenceContractProbe.exercise()
        try LogicClockLineageContractProbe.exercise()
    }
    public static func exerciseSearch() throws(LogicKernelError) {
        var run = try context()
        let solver: any LogicSATSolving = NativeLogicSATSolver()
        for (rows, variables, satisfiable) in [([[1,2],[1,-2],[-1,2],[-1,-2]],2,false), ([[1,2,3],[-1],[-2]],3,true), ([],0,true), ([[]],0,false)] {
            let formula = try Self.formula(rows, variables: variables, context: &run)
            switch try solver.solve(formula, context: &run) {
            case .satisfiable(let assignment, _):
                guard satisfiable else { throw .invalidModel("CDCL accepted an unsatisfiable fixture") }
                try assignment.validate(formula, context: &run)
            case .unsatisfiable(let certificate, let statistics):
                guard !satisfiable else { throw .invalidModel("CDCL rejected a satisfiable fixture") }
                if variables > 0 && statistics.learnedClauses == 0 { throw .invalidModel("CDCL did not exercise conflict learning") }
                let checked = try NativeLogicRUPChecker().check(formula, certificate: certificate, context: &run)
                try checked.requireBinding(to: formula)
            }
        }
    }
}
