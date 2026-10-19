import LogicIR
import LogicKernelCore

internal enum RTLSimulationAdmission {
    static func compile(_ design: borrowing ElaboratedRTL, context: inout LogicKernelContext) throws(LogicKernelError) -> RTLSimulationPlan {
        try RTLSimulationPlan.admitSource(design, context: &context)
        var workspace = try RTLDependencyWorkspace(design: design, context: &context)
        return try workspace.run(context: &context)
    }
}
