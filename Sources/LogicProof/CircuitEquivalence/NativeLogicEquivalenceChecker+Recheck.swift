import LogicKernelCore

extension NativeLogicEquivalenceChecker: LogicEquivalenceProofRechecking {
    public func recheck(_ problem: borrowing LogicEquivalenceProblem, certificate: borrowing LogicRUPCertificate,
                        context: inout LogicKernelContext) throws(LogicKernelError) -> CheckedLogicEquivalence {
        var miter = try EquivalenceMiter.build(problem, context: &context)
        do throws(LogicKernelError) {
            let proof = try CheckedLogicEquivalence.verify(problem, formula: miter.formula,
                certificate: certificate, checker: NativeLogicRUPChecker(), context: &context)
            try miter.release(context: &context)
            return proof
        } catch { try miter.release(context: &context); throw error }
    }
}
