import LogicKernelCore

public protocol LogicProofChecking: Sendable {
    func check(_ formula: borrowing LogicCNFFormula, certificate: borrowing LogicRUPCertificate,
               context: inout LogicKernelContext) throws(LogicKernelError) -> CheckedLogicProof
}
