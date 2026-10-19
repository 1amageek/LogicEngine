import LogicKernelCore

public protocol LogicSimulationEvaluating: Sendable {
    func makeState(_ model: borrowing LogicSimulationModel, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicSimulationState
    func evaluate(_ model: borrowing LogicSimulationModel, event: borrowing LogicInputEvent,
                  state: inout LogicSimulationState, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicObservation
}
