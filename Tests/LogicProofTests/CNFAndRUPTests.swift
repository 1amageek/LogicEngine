import Testing
import LogicKernelCore
import LogicProof
import LogicProofProbeSupport

@Suite(.timeLimit(.minutes(1)))
struct CNFAndRUPTests {
    private typealias F = LogicProofContractProbe
    @Test func independentCheckerAcceptsOnlyActualContradictions() throws { try F.exercise() }
    @Test func literalsEmptyCNFAndDuplicateNormalization() throws {
        #expect(throws: LogicKernelError.self) { try LogicSATLiteral(0) }
        #expect(throws: LogicKernelError.self) { try LogicSATLiteral(Int.min) }
        #expect(throws: LogicKernelError.self) { try LogicSATVariable(0) }
        #expect(try LogicSATLiteral(-Int.max).negated.rawValue == Int.max)
        var run = try F.context()
        let empty = try F.formula([], variables: 0, context: &run)
        let forged = try F.certificate([[]], formula: empty, context: &run)
        #expect(throws: LogicKernelError.self) { try NativeLogicRUPChecker().check(empty, certificate: forged, context: &run) }
        let normalized = try F.formula([[1,1,-1,-1]], variables: 1, context: &run)
        #expect(normalized.literalCount == 2)
        normalized.withClauses { clauses, literals in
            #expect(clauses.count == 1 && clauses[0] == 0..<2)
            #expect(literals[0].rawValue == 1 && literals[1].rawValue == -1)
        }
    }
    @Test func failedAppendRestoresOwnedClauseTables() throws {
        var run = try F.context()
        var builder = try LogicCNFBuilder(variableCount: 1, clauseCapacity: 2, literalCapacity: 2, context: &run)
        #expect(throws: LogicKernelError.self) { try builder.appendClause([LogicSATLiteral(1), LogicSATLiteral(2)], context: &run) }
        try builder.appendClause([LogicSATLiteral(1)], context: &run)
        try builder.appendClause([LogicSATLiteral(-1)], context: &run)
        let formula = try builder.finish(context: &run)
        #expect(formula.clauseCount == 2 && formula.literalCount == 2)
        let certificate = try F.certificate([[]], formula: formula, context: &run)
        _ = try NativeLogicRUPChecker().check(formula, certificate: certificate, context: &run)
    }
    @Test func formulaBindingAndReceiptOwnerAreChecked() throws {
        var run = try F.context()
        let formula = try F.formula([[1],[-1]], variables: 2, context: &run)
        let other = try F.formula([[2],[-2]], variables: 2, context: &run)
        let copy = try F.formula([[1],[-1]], variables: 2, context: &run)
        let certificate = try F.certificate([[]], formula: formula, context: &run)
        let checker = NativeLogicRUPChecker()
        #expect(throws: LogicKernelError.self) { try checker.check(other, certificate: certificate, context: &run) }
        let checked = try checker.check(copy, certificate: certificate, context: &run)
        try checked.requireBinding(to: copy)
        #expect(throws: LogicKernelError.self) { try checked.requireBinding(to: formula) }
        #expect(throws: LogicKernelError.self) { try checked.requireBinding(to: other) }
    }
    @Test func missingFinalClauseAndPostContradictionAdditionsFail() throws {
        var run = try F.context()
        let formula = try F.formula([[1],[-1]], variables: 1, context: &run)
        #expect(throws: LogicKernelError.self) { try F.certificate([[1]], formula: formula, context: &run) }
        var builder = try LogicRUPBuilder(formula: formula, clauseCapacity: 2, literalCapacity: 1, context: &run)
        try builder.appendClause([], context: &run)
        #expect(throws: LogicKernelError.self) { try builder.appendClause([LogicSATLiteral(1)], context: &run) }
        let certificate = try builder.finish(context: &run)
        _ = try NativeLogicRUPChecker().check(formula, certificate: certificate, context: &run)
    }
    private struct Expired: LogicRunControlling { func checkpoint() throws(LogicKernelError) { throw .deadlineExceeded } }
    private struct Cancelled: LogicRunControlling { func checkpoint() throws(LogicKernelError) { throw .cancelled } }
    @Test func checkingNeverTurnsLimitsOrCancellationIntoProof() throws {
        var run = try F.context()
        let formula = try F.formula([[1],[-1]], variables: 1, context: &run)
        let certificate = try F.certificate([[]], formula: formula, context: &run)
        var expired = try F.context(control: Expired())
        #expect(throws: LogicKernelError.deadlineExceeded) { try NativeLogicRUPChecker().check(formula, certificate: certificate, context: &expired) }
        var cancelled = try F.context(control: Cancelled())
        #expect(throws: LogicKernelError.cancelled) { try NativeLogicRUPChecker().check(formula, certificate: certificate, context: &cancelled) }
        var limits: [LogicResource: UInt64] = [:]
        for resource in LogicResource.allCases { limits[resource] = 1_000_000 }
        for resource in [LogicResource.workUnits, .managedStorageBytes, .proofBytes] {
            var bounded = limits; bounded[resource] = 1
            var context = LogicKernelContext(limits: try .init(maximums: bounded), control: F.Control())
            #expect(throws: LogicKernelError.self) { try NativeLogicRUPChecker().check(formula, certificate: certificate, context: &context) }
        }
    }
    @Test func everyTwoVariableClauseSubsetAgreesWithIndependentEnumeration() throws {
        let pool = [[1],[-1],[2],[-2],[1,2],[1,-2],[-1,2],[-1,-2]]
        for mask in 0..<256 {
            var rows: [[Int]] = []
            for index in pool.indices where mask & (1 << index) != 0 { rows.append(pool[index]) }
            let satisfiable = (0..<4).contains { assignment in
                rows.allSatisfy { row in row.contains { literal in
                    let variable = literal > 0 ? literal : -literal
                    let value = assignment & (1 << (variable - 1)) != 0
                    return value == (literal > 0)
                } }
            }
            var run = try F.context()
            let formula = try F.formula(rows, variables: 2, context: &run)
            var accepted = false
            for steps in [[[]],[[1],[]],[[-1],[]],[[2],[]],[[-2],[]],[[1,-1],[]]] {
                let certificate = try F.certificate(steps, formula: formula, context: &run)
                do {
                    let checked = try NativeLogicRUPChecker().check(formula, certificate: certificate, context: &run)
                    try checked.requireBinding(to: formula)
                    #expect(!satisfiable)
                    accepted = true
                } catch LogicKernelError.invalidModel { }
            }
            #expect(accepted == !satisfiable)
        }
    }
    @Test func workspaceAndCapacityOverflowFailBeforeLargeAllocation() throws {
        var run = try F.context(limit: UInt64.max)
        #expect(throws: LogicKernelError.self) { try LogicCNFBuilder(variableCount: 0, clauseCapacity: 0, literalCapacity: Int.max, context: &run) }
        let formula = try F.formula([], variables: Int.max, context: &run)
        let certificate = try F.certificate([[]], formula: formula, context: &run)
        #expect(throws: LogicKernelError.self) { try NativeLogicRUPChecker().check(formula, certificate: certificate, context: &run) }
    }

}
