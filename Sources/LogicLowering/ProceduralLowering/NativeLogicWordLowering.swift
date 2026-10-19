import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
public struct NativeLogicWordLowering: LogicWordLowering {
    public init() {}

    public func lower(_ design: borrowing ElaboratedRTL, context: inout LogicKernelContext)
        throws(LogicKernelError) -> WordLogicDesign {
        let scalar = WordLogicType(width: try LogicBitWidth(1))
        let receipt = try context.reserveStorage(byteCount: 0)
        var workspace = ProceduralLoweringWorkspace(receipt: receipt, scalar: scalar)
        let result: WordLogicDesign
        do throws(LogicKernelError) {
            result = try workspace.lower(design, context: &context)
        } catch {
            try workspace.release(context: &context)
            throw error
        }
        try workspace.release(context: &context)
        return result
    }
}
