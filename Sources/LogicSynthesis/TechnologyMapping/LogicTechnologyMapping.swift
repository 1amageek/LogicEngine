import LogicIR
import LogicKernelCore

public protocol LogicTechnologyMapping: Sendable {
    func map(_ design: borrowing BitLogicDesign, library: borrowing LogicTechnologyLibrary,
             policy: borrowing LogicMappingPolicy, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicMappingCandidate
}
