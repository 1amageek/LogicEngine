import LogicIR
import LogicKernelCore

// This non-Sendable workspace is retained exclusively by noncopyable public state.
// No reference escapes the module; evaluation requires that state's unique inout.
internal final class RTLEventWorkspace {
    let plan: RTLSimulationPlan
    var values: [LogicFourStateVector]
    var expressions: [LogicFourStateVector?]
    var generations: [UInt64]
    var generation: UInt64 = 1
    var frozenDepth = 0
    var expressionStack: [Int] = []
    var statementStack: [Int] = []
    var pending: [LogicBit]
    var pendingMask: [Bool]
    var dirty: [Bool]
    var activated: [Bool]
    var clocks: [LogicBit]
    var resets: [LogicBit]
    init(plan: RTLSimulationPlan, values: consuming [LogicFourStateVector]) {
        self.plan = plan; self.values = values
        expressions = .init(repeating: nil, count: plan.design.expressionCount)
        generations = .init(repeating: 0, count: plan.design.expressionCount)
        pending = .init(repeating: .unknown, count: plan.bitCount)
        pendingMask = .init(repeating: false, count: plan.bitCount)
        dirty = .init(repeating: false, count: plan.design.processCount)
        activated = .init(repeating: false, count: plan.design.processCount)
        clocks = .init(repeating: .unknown, count: plan.design.processCount)
        resets = .init(repeating: .unknown, count: plan.design.processCount)
        expressionStack.reserveCapacity(plan.design.expressionCount)
        statementStack.reserveCapacity(plan.statementStackCapacity)
    }
    func invalidateExpressions() throws(LogicKernelError) {
        guard frozenDepth == 0 else { return }
        let next = generation.addingReportingOverflow(1)
        guard !next.overflow else { throw .invalidInput("Simulation expression generation exhausted") }
        generation = next.partialValue
    }
    func changed(bit: Int, executing: Int, context: inout LogicKernelContext) throws(LogicKernelError) {
        for process in dirty.indices {
            try context.charge(.workUnits)
            if process != executing, plan.reads[process * plan.bitCount + bit] { dirty[process] = true }
        }
    }
}
