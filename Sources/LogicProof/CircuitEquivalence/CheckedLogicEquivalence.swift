import LogicKernelCore

public struct CheckedLogicEquivalence: Sendable {
    public enum Kind: Sendable { case combinational, statePreservingInduction }
    public let kind: Kind
    public let proof: CheckedLogicProof
    private let problem: LogicEquivalenceProblem
    private init(problem: LogicEquivalenceProblem, proof: CheckedLogicProof) {
        self.problem = problem; self.proof = proof
        kind = problem.stateBitCount == 0 ? .combinational : .statePreservingInduction
    }
    public func requireBinding(to problem: borrowing LogicEquivalenceProblem) throws(LogicKernelError) {
        guard self.problem.storage === problem.storage else { throw .invalidInput("Checked equivalence belongs to another problem owner") }
    }
    internal static func verify(_ problem: borrowing LogicEquivalenceProblem, formula: borrowing LogicCNFFormula,
                                certificate: borrowing LogicRUPCertificate, checker: any LogicProofChecking,
                                context: inout LogicKernelContext) throws(LogicKernelError) -> Self {
        let proof = try checker.check(formula, certificate: certificate, context: &context)
        try proof.requireBinding(to: formula)
        return .init(problem: copy problem, proof: proof)
    }
}
