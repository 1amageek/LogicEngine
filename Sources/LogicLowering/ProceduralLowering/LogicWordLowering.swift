import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
public protocol LogicWordLowering: Sendable {
    func lower(_ design: borrowing ElaboratedRTL, context: inout LogicKernelContext)
        throws(LogicKernelError) -> WordLogicDesign
}
