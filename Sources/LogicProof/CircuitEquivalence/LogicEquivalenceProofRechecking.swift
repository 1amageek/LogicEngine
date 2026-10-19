import LogicKernelCore

public protocol LogicEquivalenceProofRechecking: Sendable {
    func recheck(_ problem: borrowing LogicEquivalenceProblem, certificate: borrowing LogicRUPCertificate,
                 context: inout LogicKernelContext) throws(LogicKernelError) -> CheckedLogicEquivalence
}
