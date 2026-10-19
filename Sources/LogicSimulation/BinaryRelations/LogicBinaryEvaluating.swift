import LogicKernelCore

public protocol LogicBinaryEvaluating: Sendable {
    func evaluate(_ design: borrowing LogicBinaryDesign, inputs: borrowing Span<Bool>, currentState: borrowing Span<Bool>,
                  context: inout LogicKernelContext) throws(LogicKernelError) -> LogicBinaryObservation
    func replayInitialEvent(_ design: borrowing LogicBinaryDesign, inputs: borrowing Span<Bool>, initialState: borrowing Span<Bool>,
                            previousControl: Bool, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicBinaryEventObservation
    func replayInitialEvent(_ design: borrowing LogicBinaryDesign, inputs: borrowing Span<Bool>, initialState: borrowing Span<Bool>,
                            previousControls: borrowing Span<Bool>, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicBinaryEventObservation
}
