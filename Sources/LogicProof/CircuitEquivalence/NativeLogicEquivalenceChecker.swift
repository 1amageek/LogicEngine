import LogicKernelCore

public struct NativeLogicEquivalenceChecker: LogicEquivalenceChecking {
    private let solver: any LogicSATSolving
    private let checker: any LogicProofChecking
    public init(solver: any LogicSATSolving = NativeLogicSATSolver(), checker: any LogicProofChecking = NativeLogicRUPChecker()) {
        self.solver = solver; self.checker = checker
    }
    public func check(_ problem: borrowing LogicEquivalenceProblem, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicEquivalenceVerdict {
        do throws(LogicKernelError) {
            var miter = try EquivalenceMiter.build(problem, context: &context)
            do throws(LogicKernelError) {
                let verdict: LogicEquivalenceVerdict
                switch try solver.solve(miter.formula, context: &context) {
                case .unsatisfiable(let certificate, _):
                    verdict = .equivalent(try CheckedLogicEquivalence.verify(problem, formula: miter.formula,
                        certificate: certificate, checker: checker, context: &context))
                case .satisfiable(let assignment, _):
                    let witness = try LogicEquivalenceCounterexample.replay(problem, miter: miter, assignment: assignment, context: &context)
                    if !witness.isAllowedInitialState { verdict = .inconclusive(.initialStateReachabilityNotEstablished(witness)) }
                    else if !witness.hasConcreteEventDifference { verdict = .inconclusive(.eventDifferenceNotEstablished(witness)) }
                    else { verdict = .different(witness) }
                }
                try miter.release(context: &context); return verdict
            } catch { try miter.release(context: &context); throw error }
        } catch {
            switch error {
            case .resourceLimit, .cancelled, .deadlineExceeded: return .inconclusive(.interrupted(error))
            default: throw error
            }
        }
    }
}
