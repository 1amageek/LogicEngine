import LogicIR
import LogicKernelCore

public struct NativeLogicOptimizer: LogicOptimizing {
    public init() {}
    public func optimize(_ design: borrowing BitLogicDesign, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicOptimizationCandidate {
        var workspace = try OptimizationWorkspace(source: design, context: &context)
        do throws(LogicKernelError) {
            let result = try workspace.run(source: design, context: &context)
            try workspace.release(context: &context)
            return result
        } catch {
            try workspace.release(context: &context)
            throw error
        }
    }
}
