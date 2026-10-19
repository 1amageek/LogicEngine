import LogicIR
import LogicKernelCore

public struct NativeLogicSimulationEvaluator: LogicSimulationEvaluating {
    public init() {}
    public func makeState(_ model: borrowing LogicSimulationModel, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicSimulationState {
        if let plan = model.storage.rtl { return try makeRTLState(model, plan: plan, context: &context) }
        let owner = model.storage
        guard let design = owner.mapped else { throw .invalidModel("Simulation model has no mapped design") }
        try owner.admit(context: &context)
        let arrays = design.instanceCount.multipliedReportingOverflow(by: 3)
        let combined = arrays.partialValue.addingReportingOverflow(design.netCount)
        let all = combined.partialValue.addingReportingOverflow(owner.scratchCount)
        let bytes = UInt64(max(0, all.partialValue)).multipliedReportingOverflow(by: UInt64(MemoryLayout<LogicBit>.stride))
        guard !arrays.overflow, !combined.overflow, !all.overflow, !bytes.overflow else { throw .invalidInput("Simulation state capacity overflows") }
        let total = bytes.partialValue.addingReportingOverflow(UInt64(MemoryLayout<LogicSimulationState>.stride))
        guard !total.overflow else { throw .invalidInput("Simulation state metadata overflows") }
        _ = try context.reserveStorage(byteCount: total.partialValue)
        try context.charge(.states, amount: UInt64(design.stateCount))
        var state = LogicSimulationState(owner: owner, values: .init(repeating: .unknown, count: design.netCount),
            states: .init(repeating: .unknown, count: design.instanceCount), pending: .init(repeating: .unknown, count: design.instanceCount),
            previousControls: .init(repeating: .unknown, count: design.instanceCount), functions: .init(repeating: .unknown, count: owner.scratchCount))
        try design.withTables { _, instances, _, _, _, _ throws(LogicKernelError) in
            for index in instances.indices {
                try context.charge(.workUnits)
                if let initial = instances[index].initialValue { state.states[index] = initial ? .one : .zero }
            }
        }
        try stabilize(design, state: &state, context: &context)
        return state
    }
    public func evaluate(_ model: borrowing LogicSimulationModel, event: borrowing LogicInputEvent,
                         state: inout LogicSimulationState, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicObservation {
        try context.checkpoint()
        guard state.owner === model.storage, state.valid else { throw .invalidInput("Simulation state is invalid or belongs to another model") }
        guard event.time >= state.time else { throw .invalidInput("Simulation event time decreased") }
        if let workspace = state.rtl { return try evaluateRTL(model, event: event, state: &state, workspace: workspace, context: &context) }
        guard let design = model.storage.mapped else { throw .invalidModel("Simulation model has no mapped design") }
        try design.withTables { _, _, _, ports, _, _ throws(LogicKernelError) in
            for index in event.updates.indices {
                try context.charge(.workUnits)
                let update = event.updates[index]
                guard ports.indices.contains(update.portIndex), ports[update.portIndex].direction == .input,
                      update.value.width.value == ports[update.portIndex].bits.count else { throw .invalidInput("Simulation input port or width is invalid") }
                for previous in 0..<index {
                    try context.charge(.workUnits)
                    guard event.updates[previous].portIndex != update.portIndex else { throw .invalidInput("Duplicate input update in one event") }
                }
            }
        }
        state.valid = false
        try design.withTables { _, _, _, ports, bits, _ throws(LogicKernelError) in
            for index in event.updates.indices {
                let update = event.updates[index]; let port = ports[update.portIndex]
                for bit in 0..<port.bits.count {
                    try context.charge(.workUnits)
                    state.values[bits[port.bits.lowerBound + bit].rawValue] = try update.value.bit(at: bit)
                }
            }
        }
        try stabilize(design, state: &state, context: &context)
        let observation = try observe(design, time: event.time, state: &state, context: &context)
        state.time = event.time; state.valid = true
        return observation
    }
}
