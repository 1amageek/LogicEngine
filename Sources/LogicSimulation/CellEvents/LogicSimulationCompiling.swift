import LogicIR
import LogicKernelCore

public protocol LogicSimulationCompiling: Sendable {
    func compile(_ design: borrowing ElaboratedRTL, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicSimulationModel
    func compile(_ design: borrowing MappedGateDesign, library: borrowing LogicTechnologyLibrary,
                 context: inout LogicKernelContext) throws(LogicKernelError) -> LogicSimulationModel
}
