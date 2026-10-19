import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
public struct NativeLogicBitLowering: LogicBitLowering {
    public init() {}

    public func lower(_ design: borrowing WordLogicDesign, context: inout LogicKernelContext)
        throws(LogicKernelError) -> BitLogicDesign {
        try design.withTables { (nodes: borrowing Span<WordLogicNode>, operands: borrowing Span<WordNodeIndex>,
                                 ports: borrowing Span<WordLogicPort>, states: borrowing Span<WordLogicState>,
                                 order: borrowing Span<WordNodeIndex>) throws(LogicKernelError) in
            let plan = try BitExpansionPlan(nodes: nodes, operands: operands, ports: ports,
                                            states: states, context: &context)
            let reservation = try context.reserveStorage(byteCount: plan.workspaceBytes)
            let result: BitLogicDesign
            do throws(LogicKernelError) {
                let builder = try BitLogicBuilder(capacity: plan.capacity, context: &context)
                var workspace = BitExpansionWorkspace(plan: plan, nodeCount: nodes.count,
                                                       stateCount: states.count, builder: builder)
                try workspace.expand(nodes: nodes, operands: operands, ports: ports, states: states,
                                     order: order, context: &context)
                result = try workspace.finish(context: &context)
            } catch {
                try context.releaseStorage(reservation)
                throw error
            }
            try context.releaseStorage(reservation)
            return result
        }
    }
}
