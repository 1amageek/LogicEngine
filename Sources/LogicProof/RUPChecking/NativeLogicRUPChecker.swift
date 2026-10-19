import LogicKernelCore

public struct NativeLogicRUPChecker: LogicProofChecking {
    public init() {}
    public func check(_ formula: borrowing LogicCNFFormula, certificate: borrowing LogicRUPCertificate,
                      context: inout LogicKernelContext) throws(LogicKernelError) -> CheckedLogicProof {
        try CheckedLogicProof.independentlyCheck(formula, certificate: certificate, context: &context)
    }
}
