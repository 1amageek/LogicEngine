import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
public protocol LogicBitLowering: Sendable {
    func lower(_ design: borrowing WordLogicDesign, context: inout LogicKernelContext)
        throws(LogicKernelError) -> BitLogicDesign
}
