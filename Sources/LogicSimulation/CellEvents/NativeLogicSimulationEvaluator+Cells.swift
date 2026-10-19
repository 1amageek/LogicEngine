import LogicIR
import LogicKernelCore

extension NativeLogicSimulationEvaluator {
    internal func function(_ function: LogicBooleanFunction, instance: Int, instances: borrowing Span<MappedGateInstance>,
                           pins: borrowing Span<MappedNetIndex>, state: inout LogicSimulationState,
                           context: inout LogicKernelContext) throws(LogicKernelError) -> LogicBit {
        let binding = instances[instance]
        return try function.withOperations { operations throws(LogicKernelError) in
            for index in operations.indices {
                try context.charge(.workUnits)
                let value: LogicBit
                switch operations[index] {
                case .constant(let bit): value = bit ? .one : .zero
                case .input(let slot):
                    let input = slot == binding.pins.count ? state.states[instance]
                        : state.values[pins[binding.pins.lowerBound + slot].rawValue]
                    value = input == .highImpedance ? .unknown : input
                case .invert(let a): value = state.functions[a.rawValue].inverted
                case .and(let a, let b): value = state.functions[a.rawValue].and(state.functions[b.rawValue])
                case .or(let a, let b): value = state.functions[a.rawValue].or(state.functions[b.rawValue])
                case .xor(let a, let b): value = state.functions[a.rawValue].xor(state.functions[b.rawValue])
                }
                state.functions[index] = value
            }
            return state.functions[function.output.rawValue]
        }
    }
    internal func stabilize(_ design: borrowing MappedGateDesign, state: inout LogicSimulationState,
                            context: inout LogicKernelContext) throws(LogicKernelError) {
        try design.withTables { nets, instances, pins, _, _, order throws(LogicKernelError) in
            while true {
                try context.charge(.workUnits)
                for position in order.indices {
                    try context.charge(.workUnits)
                    switch order[position] {
                    case .net(let net):
                        switch nets[net.rawValue].driver {
                        case .input: break
                        case .constant(let bit): state.values[net.rawValue] = bit ? .one : .zero
                        case .instanceOutput(let instance, let pin):
                            let cell = try design.library.cell(at: instances[instance.rawValue].cell)
                            guard let output = try cell.pin(at: pin).function else { throw .invalidModel("Validated mapped output lost its function") }
                            state.values[net.rawValue] = try function(output, instance: instance.rawValue, instances: instances,
                                pins: pins, state: &state, context: &context)
                        }
                    case .state(let instance):
                        let index = instance.rawValue
                        let cell = try design.library.cell(at: instances[index].cell)
                        guard let definition = cell.state else { throw .invalidModel("Validated mapped state lost its definition") }
                        guard case .latch(let gate, let positive) = definition.control else { continue }
                        let control = state.values[pins[instances[index].pins.lowerBound + gate.rawValue].rawValue]
                        let data = try function(definition.nextState, instance: index, instances: instances, pins: pins, state: &state, context: &context)
                        let level = LogicCellEventSemantics.level(control, positive: positive)
                        var value = level == .one ? data : level == .zero ? state.states[index] : LogicCellEventSemantics.merge(data, state.states[index])
                        if let reset = definition.asynchronousReset {
                            let signal = state.values[pins[instances[index].pins.lowerBound + reset.pin.rawValue].rawValue]
                            value = LogicCellEventSemantics.reset(LogicCellEventSemantics.level(signal, positive: reset.activeHigh), value: reset.value, otherwise: value)
                        }
                        state.states[index] = value
                    }
                }
                // Sample all FFs before changing any Q. Scratch is reused; pending is
                // a separately admitted buffer, not a copy of the signal table.
                var changed = false
                for index in instances.indices {
                    try context.charge(.workUnits)
                    let cell = try design.library.cell(at: instances[index].cell)
                    guard let definition = cell.state, case .flipFlop(let clock, let rising) = definition.control else { continue }
                    let control = state.values[pins[instances[index].pins.lowerBound + clock.rawValue].rawValue]
                    var value = state.states[index]
                    if LogicCellEventSemantics.edge(from: state.previousControls[index], to: control, rising: rising) {
                        value = try function(definition.nextState, instance: index, instances: instances, pins: pins, state: &state, context: &context)
                    }
                    state.previousControls[index] = control
                    if let reset = definition.asynchronousReset {
                        let signal = state.values[pins[instances[index].pins.lowerBound + reset.pin.rawValue].rawValue]
                        value = LogicCellEventSemantics.reset(LogicCellEventSemantics.level(signal, positive: reset.activeHigh), value: reset.value, otherwise: value)
                    }
                    state.pending[index] = value
                    if value != state.states[index] { changed = true }
                }
                for index in instances.indices {
                    try context.charge(.workUnits)
                    let cell = try design.library.cell(at: instances[index].cell)
                    if let definition = cell.state, case .flipFlop = definition.control { state.states[index] = state.pending[index] }
                }
                if !changed { break }
            }
        }
    }
}
