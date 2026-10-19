import LogicIR
import LogicKernelCore

public struct NativeLogicBinaryEvaluator: LogicBinaryEvaluating {
    public init() {}
    public func evaluate(_ design: borrowing LogicBinaryDesign, inputs: borrowing Span<Bool>, currentState: borrowing Span<Bool>,
                         context: inout LogicKernelContext) throws(LogicKernelError) -> LogicBinaryObservation {
        try context.checkpoint()
        guard currentState.count == design.stateCount else { throw .invalidInput("Binary current-state dimension does not match design") }
        var workspace = try makeWorkspace(design, context: &context)
        do throws(LogicKernelError) {
            try fill(design, inputs: inputs, currentState: currentState, workspace: &workspace, context: &context)
            let result = try workspace.publish(context: &context)
            try workspace.release(context: &context); return result
        } catch { try workspace.release(context: &context); throw error }
    }
    public func replayInitialEvent(_ design: borrowing LogicBinaryDesign, inputs: borrowing Span<Bool>, initialState: borrowing Span<Bool>,
                                   previousControl: Bool, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicBinaryEventObservation {
        try context.checkpoint()
        guard initialState.count == design.stateCount else { throw .invalidInput("Binary initial-state dimension does not match design") }
        var workspace = try makeWorkspace(design, context: &context)
        do throws(LogicKernelError) {
            for index in initialState.indices {
                try context.charge(.workUnits)
                workspace.eventStates[index] = initialState[index]; workspace.previousControls[index] = previousControl
            }
            return try replay(design, inputs: inputs, workspace: &workspace, context: &context)
        } catch { try workspace.release(context: &context); throw error }
    }
    public func replayInitialEvent(_ design: borrowing LogicBinaryDesign, inputs: borrowing Span<Bool>, initialState: borrowing Span<Bool>,
                                   previousControls: borrowing Span<Bool>, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicBinaryEventObservation {
        try context.checkpoint()
        guard initialState.count == design.stateCount, previousControls.count == design.stateCount else {
            throw .invalidInput("Binary initial-state or physical history dimension does not match design")
        }
        var workspace = try makeWorkspace(design, context: &context)
        do throws(LogicKernelError) {
            for index in initialState.indices {
                try context.charge(.workUnits)
                workspace.eventStates[index] = initialState[index]
                workspace.previousControls[index] = previousControls[index]
            }
            return try replay(design, inputs: inputs, workspace: &workspace, context: &context)
        } catch { try workspace.release(context: &context); throw error }
    }
    private func replay(_ design: borrowing LogicBinaryDesign, inputs: borrowing Span<Bool>,
                        workspace: inout BinaryRelationWorkspace, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicBinaryEventObservation {
            while true {
                try context.charge(.workUnits)
                // Retain the state allocation during the scoped borrow; fill mutates other tables only.
                do {
                    let current = workspace.eventStates
                    try fill(design, inputs: inputs, currentState: current.span, workspace: &workspace, context: &context)
                }
                var changed = false
                for index in workspace.actions.indices {
                    try context.charge(.workUnits)
                    let action = workspace.actions[index]
                    let next: Bool
                    switch action.kind {
                    case .latch: next = action.sampled
                    case .flipFlop(let rising):
                        let edge = rising ? !workspace.previousControls[index] && action.control : workspace.previousControls[index] && !action.control
                        next = edge ? action.sampled : action.asynchronous
                    }
                    workspace.previousControls[index] = action.control
                    if next != workspace.eventStates[index] { changed = true }
                    workspace.eventStates[index] = next
                }
                if !changed {
                    let relation = try workspace.publish(context: &context)
                    _ = try context.reserveStorage(byteCount: UInt64(workspace.eventStates.count) + LogicBinaryEventObservation.storageByteCount)
                    try context.charge(.outputBytes, amount: UInt64(workspace.eventStates.count))
                    let result = LogicBinaryEventObservation(observation: relation, states: workspace.eventStates)
                    try workspace.release(context: &context); return result
                }
            }
    }
    private func makeWorkspace(_ design: borrowing LogicBinaryDesign, context: inout LogicKernelContext) throws(LogicKernelError) -> BinaryRelationWorkspace {
        switch design {
        case .bit(let graph): return try .init(nodes: graph.nodeCount, functionNodes: 0, instances: 0, states: graph.stateCount,
                                               outputCapacity: graph.portBitCount, context: &context)
        case .mapped(let graph):
        var maximum = 0
        try graph.withTables { _, instances, _, _, _, _ throws(LogicKernelError) in
            for index in instances.indices {
                try context.charge(.workUnits)
                let cell = try graph.library.cell(at: instances[index].cell)
                try cell.withPins { pins throws(LogicKernelError) in
                    for pin in pins.indices { try context.charge(.workUnits); maximum = max(maximum, pins[pin].function?.nodeCount ?? 0) }
                }
                maximum = max(maximum, cell.state?.nextState.nodeCount ?? 0)
            }
        }
        return try .init(nodes: graph.netCount, functionNodes: maximum, instances: graph.instanceCount,
            states: graph.stateCount, outputCapacity: graph.portBitCount, context: &context)
        }
    }
    private func fill(_ design: borrowing LogicBinaryDesign, inputs: borrowing Span<Bool>, currentState: borrowing Span<Bool>,
                      workspace: inout BinaryRelationWorkspace, context: inout LogicKernelContext) throws(LogicKernelError) {
        workspace.outputs.removeAll(keepingCapacity: true); workspace.actions.removeAll(keepingCapacity: true)
        switch design {
        case .bit(let graph): try fillBit(graph, inputs: inputs, currentState: currentState, workspace: &workspace, context: &context)
        case .mapped(let graph): try fillMapped(graph, inputs: inputs, currentState: currentState, workspace: &workspace, context: &context)
        }
    }
    private func fillBit(_ graph: borrowing BitLogicDesign, inputs: borrowing Span<Bool>, currentState: borrowing Span<Bool>,
                         workspace: inout BinaryRelationWorkspace, context: inout LogicKernelContext) throws(LogicKernelError) {
            return try graph.withTables { (nodes: borrowing Span<BitLogicNode>, operands: borrowing Span<BitNodeIndex>, ports: borrowing Span<BitLogicPort>, bits: borrowing Span<BitNodeIndex>, states: borrowing Span<BitLogicState>, order: borrowing Span<BitNodeIndex>) throws(LogicKernelError) in
                var input = 0
                for port in ports.indices where ports[port].direction == .input {
                    for offset in ports[port].bits {
                        try context.charge(.workUnits)
                        guard input < inputs.count else { throw .invalidInput("Missing binary input bit") }
                        workspace.values[bits[offset].rawValue] = inputs[input]; input += 1
                    }
                }
                guard input == inputs.count else { throw .invalidInput("Extra binary input bit") }
                for offset in order.indices {
                    try context.charge(.workUnits)
                    let index = order[offset].rawValue; let node = nodes[index]; let start = node.operands.lowerBound
                    switch node.operation {
                    case .input: break
                    case .constant(let value): workspace.values[index] = value
                    case .state(let state): workspace.values[index] = currentState[state.rawValue]
                    case .buffer: workspace.values[index] = workspace.values[operands[start].rawValue]
                    case .invert: workspace.values[index] = !workspace.values[operands[start].rawValue]
                    case .and: workspace.values[index] = workspace.values[operands[start].rawValue] && workspace.values[operands[start + 1].rawValue]
                    case .or: workspace.values[index] = workspace.values[operands[start].rawValue] || workspace.values[operands[start + 1].rawValue]
                    case .xor: workspace.values[index] = workspace.values[operands[start].rawValue] != workspace.values[operands[start + 1].rawValue]
                    case .select: workspace.values[index] = workspace.values[operands[start].rawValue] ? workspace.values[operands[start + 1].rawValue] : workspace.values[operands[start + 2].rawValue]
                    }
                }
                for index in states.indices {
                    try context.charge(.workUnits)
                    let state = states[index]; let q = currentState[index]
                    var sampled = workspace.values[state.next.rawValue]
                    let kind: LogicBinaryStateAction.Kind; let control: Bool; let reset: BitReset?
                    switch state.control {
                    case .flipFlop(let clock, let edge, let enable, let definition):
                        kind = .flipFlop(risingEdge: edge == .rising); control = workspace.values[clock.rawValue]; reset = definition
                        if let enable, !workspace.values[enable.rawValue] { sampled = q }
                    case .latch(let gate, let positive, let definition):
                        kind = .latch; control = workspace.values[gate.rawValue] == positive; reset = definition
                        if !control { sampled = q }
                    }
                    var asynchronous = q
                    if let reset, workspace.values[reset.signal.rawValue] == reset.activeHigh {
                        sampled = reset.value
                        if reset.kind == .asynchronous { asynchronous = reset.value }
                    }
                    workspace.actions.append(.init(kind: kind, control: control, sampled: sampled, asynchronous: asynchronous))
                }
                for port in ports.indices where ports[port].direction == .output {
                    for offset in ports[port].bits { try context.charge(.workUnits); workspace.outputs.append(workspace.values[bits[offset].rawValue]) }
                }
            }
    }
    private func fillMapped(_ graph: borrowing MappedGateDesign, inputs: borrowing Span<Bool>, currentState: borrowing Span<Bool>,
                            workspace: inout BinaryRelationWorkspace, context: inout LogicKernelContext) throws(LogicKernelError) {
            try graph.withTables { nets, instances, pins, ports, bits, order throws(LogicKernelError) in
                var ordinal = 0
                for index in instances.indices where instances[index].stateID != nil { workspace.stateForInstance[index] = ordinal; ordinal += 1 }
                var input = 0
                for port in ports.indices where ports[port].direction == .input {
                    for offset in ports[port].bits {
                        try context.charge(.workUnits)
                        guard input < inputs.count else { throw .invalidInput("Missing binary mapped input bit") }
                        workspace.values[bits[offset].rawValue] = inputs[input]; input += 1
                    }
                }
                guard input == inputs.count else { throw .invalidInput("Extra binary mapped input bit") }
                for offset in order.indices {
                    try context.charge(.workUnits)
                    guard case .net(let net) = order[offset] else { continue }
                    switch nets[net.rawValue].driver {
                    case .input: break
                    case .constant(let value): workspace.values[net.rawValue] = value
                    case .instanceOutput(let index, let pin):
                        let instance = instances[index.rawValue]; let cell = try graph.library.cell(at: instance.cell)
                        guard let function = try cell.pin(at: pin).function else { throw .invalidModel("Mapped binary output has no actual function") }
                        let state = workspace.stateForInstance[index.rawValue]
                        workspace.values[net.rawValue] = try workspace.function(function, instance: instance, pins: pins,
                            state: state < 0 ? false : currentState[state], context: &context)
                    }
                }
                for index in instances.indices {
                    try context.charge(.workUnits)
                    let instance = instances[index]; let cell = try graph.library.cell(at: instance.cell)
                    guard let definition = cell.state else { continue }
                    let q = currentState[workspace.stateForInstance[index]]
                    var sampled = try workspace.function(definition.nextState, instance: instance, pins: pins, state: q, context: &context)
                    let signal = workspace.values[pins[instance.pins.lowerBound + definition.control.pin.rawValue].rawValue]
                    let kind: LogicBinaryStateAction.Kind; let control: Bool
                    switch definition.control {
                    case .flipFlop(_, let rising): kind = .flipFlop(risingEdge: rising); control = signal
                    case .latch(_, let positive): kind = .latch; control = signal == positive; if !control { sampled = q }
                    }
                    var asynchronous = q
                    if let reset = definition.asynchronousReset,
                       workspace.values[pins[instance.pins.lowerBound + reset.pin.rawValue].rawValue] == reset.activeHigh {
                        sampled = reset.value; asynchronous = reset.value
                    }
                    workspace.actions.append(.init(kind: kind, control: control, sampled: sampled, asynchronous: asynchronous))
                }
                for port in ports.indices where ports[port].direction == .output {
                    for offset in ports[port].bits { try context.charge(.workUnits); workspace.outputs.append(workspace.values[bits[offset].rawValue]) }
                }
            }
    }
}
