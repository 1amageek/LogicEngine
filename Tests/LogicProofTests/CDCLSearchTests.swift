import Testing
import LogicKernelCore
import LogicProof
import LogicProofProbeSupport
import Synchronization

@Suite(.timeLimit(.minutes(1)))
struct CDCLSearchTests {
    private typealias F = LogicProofContractProbe
    private func truth(_ rows: [[Int]], variables: Int) -> Bool {
        (0..<(1 << variables)).contains { assignment in
            rows.allSatisfy { row in row.contains { literal in
                let variable = literal > 0 ? literal : -literal
                return (assignment & (1 << (variable - 1)) != 0) == (literal > 0)
            } }
        }
    }
    private func verify(_ rows: [[Int]], variables: Int) throws -> LogicSATStatistics {
        var run = try F.context()
        let formula = try F.formula(rows, variables: variables, context: &run)
        let solver: any LogicSATSolving = NativeLogicSATSolver()
        let result = try solver.solve(formula, context: &run)
        switch result {
        case .satisfiable(let assignment, let statistics):
            #expect(truth(rows, variables: variables))
            try assignment.validate(formula, context: &run)
            for variable in 1..<(variables + 1) { _ = try assignment.value(of: .init(variable)) }
            return statistics
        case .unsatisfiable(let certificate, let statistics):
            #expect(!truth(rows, variables: variables))
            let checked = try NativeLogicRUPChecker().check(formula, certificate: certificate, context: &run)
            try checked.requireBinding(to: formula)
            #expect(certificate.additionCount == Int(statistics.learnedClauses) + 1)
            return statistics
        }
    }
    @Test func everyTwoVariableFormulaMatchesTruthAndIndependentProof() throws {
        let pool = [[1],[-1],[2],[-2],[1,2],[1,-2],[-1,2],[-1,-2]]
        for mask in 0..<256 {
            var rows: [[Int]] = []
            for index in pool.indices where mask & (1 << index) != 0 { rows.append(pool[index]) }
            _ = try verify(rows, variables: 2)
        }
        for (rows, variables) in [([],0),([[]],0),([[1,-1,1],[2,-2]],3),([[1],[-1]],1),([[1,2,3],[-1],[-2]],3)] {
            _ = try verify(rows, variables: variables)
        }
    }
    @Test func deterministicSeededSearchExercisesLearningRelocationAndBackjumps() throws {
        var seed: UInt64 = 0x5A17
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 32) % UInt64(bound))
        }
        var learning: UInt64 = 0; var relocation: UInt64 = 0; var jumps: UInt64 = 0
        for _ in 0..<600 {
            var rows: [[Int]] = []
            for _ in 0..<(8 + next(28)) {
                var row: [Int] = []
                for _ in 0..<(2 + next(3)) { let variable = 1 + next(7); row.append(next(2) == 0 ? variable : -variable) }
                rows.append(row)
            }
            let first = try verify(rows, variables: 7)
            let second = try verify(rows, variables: 7)
            #expect(first == second)
            learning += first.learnedClauses; relocation += first.watchRelocations; jumps += first.nonChronologicalBackjumps
        }
        #expect(learning > 0 && relocation > 0 && jumps > 0)
    }
    @Test func multiConflictProofAndPublishedResultsAreDeterministic() throws {
        var rows: [[Int]] = []
        for pigeon in 0..<4 { rows.append((0..<3).map { pigeon * 3 + $0 + 1 }) }
        for hole in 0..<3 {
            for first in 0..<4 {
                for second in (first + 1)..<4 { rows.append([-(first * 3 + hole + 1), -(second * 3 + hole + 1)]) }
            }
        }
        let stats = try verify(rows, variables: 12)
        #expect(stats.learnedClauses > 1)
        var run = try F.context()
        for clauses in [rows, [[1,2,3],[-1,-2],[-2,-3]]] {
            let formula = try F.formula(clauses, variables: 12, context: &run)
            let first = try NativeLogicSATSolver().solve(formula, context: &run)
            let second = try NativeLogicSATSolver().solve(formula, context: &run)
            switch (first, second) {
            case (.satisfiable(let a, let sa), .satisfiable(let b, let sb)):
                #expect(sa == sb)
                for variable in 1...12 { #expect(try a.value(of: .init(variable)) == b.value(of: .init(variable))) }
            case (.unsatisfiable(let a, let sa), .unsatisfiable(let b, let sb)):
                #expect(sa == sb)
                a.withAdditions { ar, av in b.withAdditions { br, bv in
                    #expect(ar.count == br.count && av.count == bv.count)
                    for index in ar.indices { #expect(ar[index] == br[index]) }
                    for index in av.indices { #expect(av[index] == bv[index]) }
                } }
            default: Issue.record("Repeated deterministic search changed its outcome")
            }
        }
    }
    private final class Interrupted: LogicRunControlling {
        private let calls = Mutex(0)
        func checkpoint() throws(LogicKernelError) {
            let stop = calls.withLock { count in count += 1; return count == 40 }
            if stop { throw .cancelled }
        }
    }
    @Test func interruptedWorkspaceReleasesEveryScratchReservation() throws {
        var source = try F.context()
        let formula = try F.formula([[1,2,3],[-1,-2],[-2,-3]], variables: 3, context: &source)
        var run = try F.context(control: Interrupted())
        #expect(throws: LogicKernelError.cancelled) { try NativeLogicSATSolver().solve(formula, context: &run) }
        #expect(run.usage[.managedStorageBytes] == 0)
        #expect(run.usage.peakManagedStorageBytes > 0)
    }
    private struct Cancelled: LogicRunControlling { func checkpoint() throws(LogicKernelError) { throw .cancelled } }
    private struct Expired: LogicRunControlling { func checkpoint() throws(LogicKernelError) { throw .deadlineExceeded } }
    @Test func failuresCannotProduceAnOutcomeAndAssignmentBindingIsExact() throws {
        var run = try F.context()
        let formula = try F.formula([[1,2],[1,-2]], variables: 3, context: &run)
        if case .satisfiable(let assignment, _) = try NativeLogicSATSolver().solve(formula, context: &run) {
            let other = try F.formula([[1,2],[1,-2]], variables: 3, context: &run)
            #expect(throws: LogicKernelError.self) { try assignment.requireBinding(to: other) }
            #expect(throws: LogicKernelError.self) { try assignment.value(of: .init(4)) }
        } else { Issue.record("Expected a satisfying assignment") }
        var cancelled = try F.context(control: Cancelled())
        #expect(throws: LogicKernelError.cancelled) { try NativeLogicSATSolver().solve(formula, context: &cancelled) }
        var expired = try F.context(control: Expired())
        #expect(throws: LogicKernelError.deadlineExceeded) { try NativeLogicSATSolver().solve(formula, context: &expired) }
        for resource in [LogicResource.searchSteps, .workUnits, .managedStorageBytes, .outputBytes, .cnfClauses, .proofBytes] {
            var limits: [LogicResource: UInt64] = [:]
            for key in LogicResource.allCases { limits[key] = 100_000_000 }
            limits[resource] = resource == .cnfClauses ? 4 : 1
            var bounded = LogicKernelContext(limits: try .init(maximums: limits), control: F.Control())
            let problem = resource == .proofBytes || resource == .cnfClauses
                ? try F.formula([[1,2],[1,-2],[-1,2],[-1,-2]], variables: 2, context: &run) : formula
            #expect(throws: LogicKernelError.self) { try NativeLogicSATSolver().solve(problem, context: &bounded) }
        }
        var overflow = try F.context(limit: UInt64.max)
        let enormous = try F.formula([], variables: Int.max, context: &overflow)
        #expect(throws: LogicKernelError.self) { try NativeLogicSATSolver().solve(enormous, context: &overflow) }
    }
}
