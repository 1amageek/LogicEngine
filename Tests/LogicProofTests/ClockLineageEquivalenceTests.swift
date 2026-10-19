import LogicKernelCore
import LogicProof
import LogicProofProbeSupport
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ClockLineageEquivalenceTests {
    @Test func actualBranchesEffectiveEdgesAndPhysicalHistories() throws {
        try LogicClockLineageContractProbe.exercise()
    }
    @Test func combinationalCounterexamplesDoNotInventFFHistories() throws {
        var run = try LogicProofContractProbe.context()
        let reference = try LogicEquivalenceContractProbe.bit(context: &run)
        let candidate = try LogicEquivalenceContractProbe.bit(inverted: true, context: &run)
        let problem = try LogicEquivalenceContractProbe.problem(.bit(reference), .bit(candidate), inputs: 2, context: &run)
        guard case .different(let witness) = try NativeLogicEquivalenceChecker().check(problem, context: &run) else {
            Issue.record("Wrong function lacked a confirmed witness"); return
        }
        let history = witness.withEventControls { _, _ in true }
        #expect(history == nil && witness.previousControl == nil)
    }
}
