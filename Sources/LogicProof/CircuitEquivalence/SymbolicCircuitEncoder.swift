import LogicIR
import LogicKernelCore
import LogicSimulation

internal struct SymbolicCircuitEncoder: ~Copyable {
    private var values: [LogicSATLiteral]
    private var functions: [LogicSATLiteral]
    private var instanceStates: [Int]
    private var outputs: [LogicSATLiteral]
    private var actions: [SymbolicRelation.Action]
    private let outputCapacity: Int
    private var receipt: LogicStorageReservation?
    private init(nodes: Int, scratch: Int, instances: Int, states: Int, ports: Int, zero: LogicSATLiteral,
                 context: inout LogicKernelContext) throws(LogicKernelError) {
        var bytes = UInt64(MemoryLayout<Self>.stride)
        for (count, stride) in [(nodes, MemoryLayout<LogicSATLiteral>.stride), (scratch, MemoryLayout<LogicSATLiteral>.stride),
                               (instances, MemoryLayout<Int>.stride), (ports, MemoryLayout<LogicSATLiteral>.stride),
                               (states, MemoryLayout<SymbolicRelation.Action>.stride)] {
            let payload = UInt64(count).multipliedReportingOverflow(by: UInt64(stride))
            let total = bytes.addingReportingOverflow(payload.partialValue)
            guard !payload.overflow, !total.overflow else { throw .invalidInput("Symbolic circuit capacity overflows") }
            bytes = total.partialValue
        }
        try context.require(.nodes, amount: UInt64(nodes)); try context.require(.states, amount: UInt64(states))
        let reservation = try context.reserveStorage(byteCount: bytes)
        values = .init(repeating: zero, count: nodes); functions = .init(repeating: zero, count: scratch)
        instanceStates = .init(repeating: -1, count: instances)
        outputs = []; outputs.reserveCapacity(ports); actions = []; actions.reserveCapacity(states)
        receipt = consume reservation
        outputCapacity = ports
    }
    private mutating func release(context: inout LogicKernelContext) throws(LogicKernelError) {
        values = []; functions = []; instanceStates = []; outputs = []; actions = []
        let reservation = receipt.take(); if let reservation { try context.releaseStorage(reservation) }
    }
    static func encode(_ design: borrowing LogicBinaryDesign, inputs: borrowing Span<LogicSATLiteral>, states: borrowing Span<LogicSATLiteral>,
                       zero: LogicSATLiteral, builder: inout TseitinBuilder, context: inout LogicKernelContext) throws(LogicKernelError) -> SymbolicRelation {
        let nodeCount: Int; let instanceCount: Int; let ports: Int
        var maximum = 0
        switch design {
        case .bit(let graph): nodeCount = graph.nodeCount; instanceCount = 0; ports = graph.portBitCount
        case .mapped(let graph):
            nodeCount = graph.netCount; instanceCount = graph.instanceCount; ports = graph.portBitCount
            try graph.withTables { _, instances, _, _, _, _ throws(LogicKernelError) in
                for index in instances.indices {
                    try context.charge(.workUnits)
                    let cell = try graph.library.cell(at: instances[index].cell)
                    try cell.withPins { pins throws(LogicKernelError) in
                        for index in pins.indices { try context.charge(.workUnits); maximum = max(maximum, pins[index].function?.nodeCount ?? 0) }
                    }
                    maximum = max(maximum, cell.state?.nextState.nodeCount ?? 0)
                }
            }
        }
        var workspace = try Self(nodes: nodeCount, scratch: maximum, instances: instanceCount, states: design.stateCount,
            ports: ports, zero: zero, context: &context)
        do throws(LogicKernelError) {
            for index in workspace.values.indices { workspace.values[index] = try builder.fresh(context: &context) }
            switch design {
            case .bit(let graph): try workspace.bit(graph, inputs: inputs, states: states, builder: &builder, context: &context)
            case .mapped(let graph): try workspace.mapped(graph, inputs: inputs, states: states, builder: &builder, context: &context)
            }
            let actionBytes = UInt64(workspace.actions.count).multipliedReportingOverflow(by: UInt64(MemoryLayout<SymbolicRelation.Action>.stride))
            let outputBytes = UInt64(workspace.outputCapacity).multipliedReportingOverflow(by: UInt64(MemoryLayout<LogicSATLiteral>.stride))
            let total = actionBytes.partialValue.addingReportingOverflow(outputBytes.partialValue)
            guard !actionBytes.overflow, !outputBytes.overflow, !total.overflow else { throw .invalidInput("Symbolic relation output overflows") }
            let reservation = try context.reserveStorage(byteCount: total.partialValue)
            let result = SymbolicRelation(outputs: workspace.outputs, actions: workspace.actions, receipt: reservation)
            try workspace.release(context: &context); return result
        } catch { try workspace.release(context: &context); throw error }
    }
    private mutating func bit(_ graph: borrowing BitLogicDesign, inputs: borrowing Span<LogicSATLiteral>, states: borrowing Span<LogicSATLiteral>,
                              builder: inout TseitinBuilder, context: inout LogicKernelContext) throws(LogicKernelError) {
        return try graph.withTables { (nodes: borrowing Span<BitLogicNode>, operands: borrowing Span<BitNodeIndex>, ports: borrowing Span<BitLogicPort>, bits: borrowing Span<BitNodeIndex>, definitions: borrowing Span<BitLogicState>, _: borrowing Span<BitNodeIndex>) throws(LogicKernelError) in
            var input = 0
            for index in ports.indices where ports[index].direction == .input {
                for offset in ports[index].bits { try builder.equate(values[bits[offset].rawValue], inputs[input], context: &context); input += 1 }
            }
            for index in nodes.indices {
                try context.charge(.workUnits)
                let node = nodes[index]; let y = values[index]; let start = node.operands.lowerBound
                let x: LogicSATLiteral
                switch node.operation {
                case .input: continue
                case .constant(let value): try builder.clause(value ? y : y.negated, context: &context); continue
                case .state(let state): x = states[state.rawValue]
                case .buffer: x = values[operands[start].rawValue]
                case .invert: x = values[operands[start].rawValue].negated
                case .and: x = try builder.and(values[operands[start].rawValue], values[operands[start + 1].rawValue], context: &context)
                case .or: x = try builder.or(values[operands[start].rawValue], values[operands[start + 1].rawValue], context: &context)
                case .xor: x = try builder.xor(values[operands[start].rawValue], values[operands[start + 1].rawValue], context: &context)
                case .select: x = try builder.select(values[operands[start].rawValue], values[operands[start + 1].rawValue], values[operands[start + 2].rawValue], context: &context)
                }
                try builder.equate(y, x, context: &context)
            }
            for index in definitions.indices {
                try context.charge(.workUnits)
                let definition = definitions[index]; let q = states[index]
                var sampled = values[definition.next.rawValue]
                let kind: LogicBinaryStateAction.Kind; let control: LogicSATLiteral; let reset: BitReset?
                switch definition.control {
                case .flipFlop(let clock, let edge, let enable, let specification):
                    kind = .flipFlop(risingEdge: edge == .rising); control = values[clock.rawValue]; reset = specification
                    if let enable { sampled = try builder.select(values[enable.rawValue], sampled, q, context: &context) }
                case .latch(let gate, let positive, let specification):
                    kind = .latch; control = positive ? values[gate.rawValue] : values[gate.rawValue].negated; reset = specification
                    sampled = try builder.select(control, sampled, q, context: &context)
                }
                var asynchronous = q
                if let reset {
                    let signal = reset.activeHigh ? values[reset.signal.rawValue] : values[reset.signal.rawValue].negated
                    let value = try builder.constant(reset.value, context: &context)
                    sampled = try builder.select(signal, value, sampled, context: &context)
                    if reset.kind == .asynchronous { asynchronous = try builder.select(signal, value, q, context: &context) }
                }
                actions.append(.init(kind: kind, control: control, sampled: sampled, asynchronous: asynchronous))
            }
            for index in ports.indices where ports[index].direction == .output {
                for offset in ports[index].bits { try context.charge(.workUnits); outputs.append(values[bits[offset].rawValue]) }
            }
        }
    }
    private mutating func function(_ function: LogicBooleanFunction, instance: MappedGateInstance, pins: borrowing Span<MappedNetIndex>,
                                   state: LogicSATLiteral?, builder: inout TseitinBuilder, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicSATLiteral {
        try function.withOperations { operations throws(LogicKernelError) in
            for index in operations.indices {
                try context.charge(.workUnits)
                switch operations[index] {
                case .constant(let value): functions[index] = try builder.constant(value, context: &context)
                case .input(let slot):
                    if slot == instance.pins.count {
                        guard let state else { throw .invalidModel("Cell function references absent state") }; functions[index] = state
                    } else { functions[index] = values[pins[instance.pins.lowerBound + slot].rawValue] }
                case .invert(let a): functions[index] = functions[a.rawValue].negated
                case .and(let a, let b): functions[index] = try builder.and(functions[a.rawValue], functions[b.rawValue], context: &context)
                case .or(let a, let b): functions[index] = try builder.or(functions[a.rawValue], functions[b.rawValue], context: &context)
                case .xor(let a, let b): functions[index] = try builder.xor(functions[a.rawValue], functions[b.rawValue], context: &context)
                }
            }
            return functions[function.output.rawValue]
        }
    }
    private mutating func mapped(_ graph: borrowing MappedGateDesign, inputs: borrowing Span<LogicSATLiteral>, states: borrowing Span<LogicSATLiteral>,
                                 builder: inout TseitinBuilder, context: inout LogicKernelContext) throws(LogicKernelError) {
        try graph.withTables { nets, instances, pins, ports, bits, _ throws(LogicKernelError) in
            var stateOrdinal = 0
            for index in instances.indices where instances[index].stateID != nil { try context.charge(.workUnits); instanceStates[index] = stateOrdinal; stateOrdinal += 1 }
            var input = 0
            for index in ports.indices where ports[index].direction == .input {
                for offset in ports[index].bits { try builder.equate(values[bits[offset].rawValue], inputs[input], context: &context); input += 1 }
            }
            for index in nets.indices {
                try context.charge(.workUnits)
                let y = values[index]
                switch nets[index].driver {
                case .input: break
                case .constant(let value): try builder.clause(value ? y : y.negated, context: &context)
                case .instanceOutput(let binding, let pin):
                    let instance = instances[binding.rawValue]; let cell = try graph.library.cell(at: instance.cell)
                    guard let definition = try cell.pin(at: pin).function else { throw .invalidModel("Mapped symbolic output has no actual function") }
                    let ordinal = instanceStates[binding.rawValue]
                    let result = try function(definition, instance: instance, pins: pins, state: ordinal < 0 ? nil : states[ordinal], builder: &builder, context: &context)
                    try builder.equate(y, result, context: &context)
                }
            }
            for index in instances.indices {
                try context.charge(.workUnits)
                let instance = instances[index]; let cell = try graph.library.cell(at: instance.cell)
                guard let definition = cell.state else { continue }
                let q = states[instanceStates[index]]
                var sampled = try function(definition.nextState, instance: instance, pins: pins, state: q, builder: &builder, context: &context)
                let signal = values[pins[instance.pins.lowerBound + definition.control.pin.rawValue].rawValue]
                let kind: LogicBinaryStateAction.Kind; let control: LogicSATLiteral
                switch definition.control {
                case .flipFlop(_, let rising): kind = .flipFlop(risingEdge: rising); control = signal
                case .latch(_, let positive):
                    kind = .latch; control = positive ? signal : signal.negated
                    sampled = try builder.select(control, sampled, q, context: &context)
                }
                var asynchronous = q
                if let reset = definition.asynchronousReset {
                    let raw = values[pins[instance.pins.lowerBound + reset.pin.rawValue].rawValue]
                    let active = reset.activeHigh ? raw : raw.negated
                    let value = try builder.constant(reset.value, context: &context)
                    sampled = try builder.select(active, value, sampled, context: &context)
                    asynchronous = try builder.select(active, value, q, context: &context)
                }
                actions.append(.init(kind: kind, control: control, sampled: sampled, asynchronous: asynchronous))
            }
            for index in ports.indices where ports[index].direction == .output {
                for offset in ports[index].bits { try context.charge(.workUnits); outputs.append(values[bits[offset].rawValue]) }
            }
        }
    }
}
