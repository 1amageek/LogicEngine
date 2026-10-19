import LogicIR
import LogicKernelCore

extension NativeLogicSimulationEvaluator {
    internal func makeRTLState(_ model: borrowing LogicSimulationModel, plan: RTLSimulationPlan, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicSimulationState {
        try plan.admit(context: &context)
        var valueBytes: UInt64 = 0
        try plan.design.withProgram { signals, statements, children, _, _, _, _ throws(LogicKernelError) in
            let stack = statements.count.multipliedReportingOverflow(by: 2)
            let capacity = stack.partialValue.addingReportingOverflow(children.count)
            guard !stack.overflow, !capacity.overflow else { throw .invalidInput("RTL execution stack capacity overflows") }
            for (count, stride) in [(signals.count, MemoryLayout<LogicFourStateVector>.stride),
                (plan.design.expressionCount, MemoryLayout<LogicFourStateVector?>.stride + MemoryLayout<UInt64>.stride + MemoryLayout<Int>.stride),
                (capacity.partialValue, MemoryLayout<Int>.stride), (plan.bitCount, MemoryLayout<LogicBit>.stride + 1),
                (plan.design.processCount, MemoryLayout<LogicBit>.stride * 2 + 2)] {
                let bytes = UInt64(count).multipliedReportingOverflow(by: UInt64(stride))
                let next = valueBytes.addingReportingOverflow(bytes.partialValue)
                guard !bytes.overflow, !next.overflow else { throw .invalidInput("RTL execution storage overflows") }; valueBytes = next.partialValue
            }
        }
        let metadata = UInt64(MemoryLayout<(RTLSimulationPlan, [LogicFourStateVector], [LogicFourStateVector?], [UInt64], UInt64, Int,
            [Int], [Int], [LogicBit], [Bool], [Bool], [Bool], [LogicBit], [LogicBit])>.stride)
        let total = valueBytes.addingReportingOverflow(metadata + UInt64(MemoryLayout<LogicSimulationState>.stride))
        guard !total.overflow else { throw .invalidInput("RTL execution metadata overflows") }
        _ = try context.reserveStorage(byteCount: total.partialValue)
        try context.charge(.states, amount: UInt64(plan.stateCount))
        var values: [LogicFourStateVector] = []; values.reserveCapacity(plan.design.signalCount)
        try plan.design.withProgram { signals, _, _, _, _, _, _ throws(LogicKernelError) in
            for index in signals.indices {
                try context.charge(.workUnits)
                if let initial = signals[index].initialValue { values.append(initial) }
                else { values.append(try .init(repeating: signals[index].defaultInitialBit, width: signals[index].type.width, context: &context)) }
            }
        }
        let workspace = RTLEventWorkspace(plan: plan, values: values)
        try plan.design.withProgram { _, statements, children, _, _, _, processes throws(LogicKernelError) in
            for index in processes.indices {
                switch processes[index].control {
                case .flipFlop(let clock, _, let reset):
                    workspace.clocks[index] = try workspace.expression(clock, context: &context).bit(at: 0)
                    if let reset { workspace.resets[index] = try workspace.expression(reset.signal, context: &context).bit(at: 0) }
                case .continuous, .combinational, .latch: workspace.dirty[index] = true
                case .levelSensitive: break
                }
            }
        }
        try workspace.stabilize(context: &context)
        return .init(owner: model.storage, rtl: workspace)
    }
    internal func evaluateRTL(_ model: borrowing LogicSimulationModel, event: borrowing LogicInputEvent,
                             state: inout LogicSimulationState, workspace: RTLEventWorkspace, context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicObservation {
        try workspace.plan.design.withProgram { signals, _, _, _, _, ports, _ throws(LogicKernelError) in
            for index in event.updates.indices {
                try context.charge(.workUnits)
                let update = event.updates[index]
                guard ports.indices.contains(update.portIndex), ports[update.portIndex].direction == .input,
                      update.value.width == signals[ports[update.portIndex].signal.rawValue].type.width else {
                    throw .invalidInput("RTL input port or width is invalid")
                }
                for previous in 0..<index {
                    try context.charge(.workUnits)
                    guard event.updates[previous].portIndex != update.portIndex else { throw .invalidInput("Duplicate RTL input event port") }
                }
            }
            state.valid = false
            for index in event.updates.indices {
                let update = event.updates[index]; let target = ports[update.portIndex].signal.rawValue
                try workspace.assign(target, selection: 0..<update.value.width.value, value: update.value, process: -1, context: &context)
            }
        }
        try workspace.stabilize(context: &context)
        let result = try workspace.plan.design.withProgram { _, _, _, _, _, ports, _ throws(LogicKernelError) in
            let payload = UInt64(ports.count).multipliedReportingOverflow(by: UInt64(MemoryLayout<LogicObservation.Output>.stride))
            guard !payload.overflow else { throw .invalidInput("RTL observation capacity overflows") }
            let total = payload.partialValue.addingReportingOverflow(UInt64(MemoryLayout<(UInt64, [LogicObservation.Output])>.stride))
            guard !total.overflow else { throw .invalidInput("RTL observation metadata overflows") }
            _ = try context.reserveStorage(byteCount: total.partialValue)
            var outputs: [LogicObservation.Output] = []; outputs.reserveCapacity(ports.count)
            for index in ports.indices where ports[index].direction == .output {
                try context.charge(.workUnits)
                let value = workspace.values[ports[index].signal.rawValue]
                try context.charge(.outputBytes, amount: UInt64(value.width.wordCount) * 16)
                outputs.append(.init(portID: ports[index].id, portIndex: index, value: value))
            }
            return LogicObservation(time: event.time, outputs: outputs)
        }
        state.time = event.time; state.valid = true
        return result
    }
}
