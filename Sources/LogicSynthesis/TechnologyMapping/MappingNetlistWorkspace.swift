import CircuiteFoundation
import LogicIR
import LogicKernelCore

internal struct MappingNetlistWorkspace: ~Copyable {
    var nets: [MappedGateNet] = []
    var instances: [MappingInstanceDraft] = []
    var mapped: [Int]
    private var needed: [Bool]
    private var stack: [Int] = []
    private var negative: [Int: MappedNetIndex] = [:]
    private var constants: [Int] = [-1, -1]
    private var ids: MappingIdentityAllocator
    let library: LogicTechnologyLibrary
    let inverter: MappingMatch?
    let realizationPolicy: MappedGateRealizationPolicy
    let tieMatches: [MappingMatch?]
    init(graph: borrowing MappingGraph, library: borrowing LogicTechnologyLibrary, policy: borrowing LogicMappingPolicy,
         inverter: MappingMatch?, tieMatches: [MappingMatch?], netCapacity: Int, instanceCapacity: Int) {
        self.library = copy library; self.inverter = inverter
        self.realizationPolicy = policy.realizationPolicy; self.tieMatches = tieMatches
        mapped = .init(repeating: -1, count: graph.nodeCount); needed = .init(repeating: false, count: graph.nodeCount)
        ids = .init(next: policy.firstEntityID.rawValue, used: [])
        ids.used.reserveCapacity(netCapacity + instanceCapacity + graph.portCount + graph.stateCount)
        nets.reserveCapacity(netCapacity); instances.reserveCapacity(instanceCapacity)
        stack.reserveCapacity(graph.nodeCount); negative.reserveCapacity(graph.nodeCount)
    }
    private mutating func addNet(_ driver: MappedGateNet.Driver, origin: LogicKernelSourceRange? = nil,
                                context: inout LogicKernelContext) throws(LogicKernelError) -> MappedNetIndex {
        try context.charge(.workUnits)
        let net = MappedNetIndex(nets.count)
        nets.append(.init(id: try ids.allocate(context: &context), driver: driver, origin: origin)); return net
    }
    private mutating func constant(_ value: Bool, context: inout LogicKernelContext) throws(LogicKernelError) -> MappedNetIndex {
        let slot = value ? 1 : 0
        if constants[slot] < 0 {
            switch realizationPolicy {
            case .standardNetlist: constants[slot] = try addNet(.constant(value), context: &context).rawValue
            case .physicalCells:
                guard let match = tieMatches[slot] else { throw .unsupported("No exact inputless tie cell realizes constant \(value ? 1 : 0)") }
                let ordinal = instances.count
                _ = try emit(match, leaves: [], origin: nil, context: &context)
                let instance = instances[ordinal]
                for pi in instance.pins.indices {
                    try context.charge(.workUnits)
                    let outputValue = match.bindings[pi]
                    if constants[outputValue] < 0 { constants[outputValue] = instance.pins[pi].rawValue }
                }
            }
        }
        return .init(constants[slot])
    }
    private mutating func invert(_ net: MappedNetIndex, context: inout LogicKernelContext) throws(LogicKernelError) -> MappedNetIndex {
        if let existing = negative[net.rawValue] { return existing }
        guard let inverter else { throw .unsupported("Library has no exact inverter implementation") }
        let output = try emit(inverter, leaves: [net], origin: nil, context: &context)
        negative[net.rawValue] = output; return output
    }
    private mutating func emit(_ match: borrowing MappingMatch, leaves: borrowing [MappedNetIndex],
                               origin: LogicKernelSourceRange?, context: inout LogicKernelContext)
        throws(LogicKernelError) -> MappedNetIndex {
        let cell = try library.cell(at: match.cell)
        var pins = [MappedNetIndex](repeating: .init(0), count: cell.pinCount)
        // Resolve inversions before assigning this instance ordinal.
        for pi in 0..<cell.pinCount where try cell.pin(at: .init(pi)).direction == .input {
            try context.charge(.workUnits); let binding = match.bindings[pi]
            if binding < 2 { pins[pi] = try constant(binding == 1, context: &context) }
            else {
                let net = leaves[(binding - 2) / 2]
                pins[pi] = binding % 2 == 0 ? net : try invert(net, context: &context)
            }
        }
        let ordinal = MappedInstanceIndex(instances.count)
        for pi in 0..<cell.pinCount where try cell.pin(at: .init(pi)).direction == .output {
            pins[pi] = try addNet(.instanceOutput(ordinal, .init(pi)), origin: origin, context: &context)
        }
        instances.append(.init(id: try ids.allocate(context: &context), cell: match.cell, pins: pins,
            stateID: nil, initial: nil, origin: origin))
        return match.invertedOutput ? try invert(pins[match.output.rawValue], context: &context) : pins[match.output.rawValue]
    }
    private mutating func mark(_ node: Int) {
        if !needed[node] { needed[node] = true; stack.append(node) }
    }
    mutating func build(_ graph: borrowing MappingGraph, cover: borrowing MappingCoverWorkspace,
                        matcher: inout MappingFunctionMatcher, context: inout LogicKernelContext)
        throws(LogicKernelError) -> MappedGateDesign {
        return try graph.withTables { nodes, _, ports, bits, states, order throws(LogicKernelError) in
            for i in ports.indices { try context.charge(.workUnits); ids.used.insert(ports[i].id) }
            for i in states.indices { try context.charge(.workUnits); ids.used.insert(states[i].id) }
            var stateMatches: [MappingMatch] = []; stateMatches.reserveCapacity(states.count)
            var rawStates: [MappedNetIndex] = []; rawStates.reserveCapacity(states.count)
            for i in states.indices {
                try context.charge(.workUnits)
                guard let match = try matcher.sequential(control: states[i].control, inverter: inverter, context: &context) else {
                    throw .unsupported("No cell has the exact state kind, edge/gate polarity, asynchronous reset and next-state function")
                }
                let cell = try library.cell(at: match.cell)
                var pins = [MappedNetIndex](repeating: .init(0), count: cell.pinCount)
                for pi in 0..<cell.pinCount where try cell.pin(at: .init(pi)).direction == .output {
                    pins[pi] = try addNet(.instanceOutput(.init(i), .init(pi)), origin: states[i].origin, context: &context)
                }
                instances.append(.init(id: try ids.allocate(context: &context), cell: match.cell, pins: pins,
                    stateID: states[i].id, initial: states[i].initialValue, origin: states[i].origin))
                stateMatches.append(match); rawStates.append(pins[match.output.rawValue])
                mark(states[i].next.rawValue)
                switch states[i].control {
                case .flipFlop(let clock, _, _, let reset): mark(clock.rawValue); if let reset { mark(reset.signal.rawValue) }
                case .latch(let gate, _, let reset): mark(gate.rawValue); if let reset { mark(reset.signal.rawValue) }
                }
            }
            for i in nodes.indices {
                try context.charge(.workUnits)
                switch nodes[i].operation {
                case .input: mapped[i] = try addNet(.input, origin: nodes[i].origin, context: &context).rawValue
                case .state(let s):
                    let net = rawStates[s.rawValue]
                    mapped[i] = try (stateMatches[s.rawValue].invertedOutput ? invert(net, context: &context) : net).rawValue
                default: break
                }
            }
            for pi in ports.indices where ports[pi].direction == .output {
                for index in ports[pi].bits { try context.charge(.workUnits); mark(bits[index].rawValue) }
            }
            while let index = stack.popLast() {
                try context.charge(.workUnits)
                guard let solution = cover.solutions[index] else { throw .unsupported("No exact functional cell cover for a live bit node") }
                for leaf in solution.cut.leaves where leaf != index { mark(leaf) }
            }
            for position in order.indices {
                try context.charge(.workUnits); let i = order[position].rawValue
                guard needed[i], mapped[i] < 0, let solution = cover.solutions[i] else { continue }
                switch solution.implementation {
                case .terminal: throw .invalidModel("Missing terminal mapping")
                case .constant(let b): mapped[i] = try constant(b, context: &context).rawValue
                case .alias(let leaf, let inverted):
                    guard mapped[leaf] >= 0 else { throw .invalidModel("Mapping cover is not topological") }
                    let net = MappedNetIndex(mapped[leaf]); mapped[i] = try (inverted ? invert(net, context: &context) : net).rawValue
                case .cell(let match):
                    var leaves: [MappedNetIndex] = []; leaves.reserveCapacity(solution.cut.leaves.count)
                    for leaf in solution.cut.leaves {
                        guard mapped[leaf] >= 0 else { throw .invalidModel("Unmapped cut input") }; leaves.append(.init(mapped[leaf]))
                    }
                    mapped[i] = try emit(match, leaves: leaves, origin: nodes[i].origin, context: &context).rawValue
                }
            }
            for i in states.indices {
                let match = stateMatches[i]; let cell = try library.cell(at: match.cell)
                guard let definition = cell.state else { throw .invalidModel("State match lost its definition") }
                for pi in 0..<cell.pinCount where try cell.pin(at: .init(pi)).direction == .input {
                    try context.charge(.workUnits)
                    let net: MappedNetIndex
                    if pi == definition.control.pin.rawValue {
                        switch states[i].control {
                        case .flipFlop(let clock, _, _, _): net = .init(mapped[clock.rawValue])
                        case .latch(let gate, _, _): net = .init(mapped[gate.rawValue])
                        }
                    } else if pi == definition.asynchronousReset?.pin.rawValue {
                        let reset: BitReset?
                        switch states[i].control { case .flipFlop(_, _, _, let r), .latch(_, _, let r): reset = r }
                        guard let reset else { throw .invalidModel("State match lost asynchronous reset") }
                        net = .init(mapped[reset.signal.rawValue])
                    } else if match.bindings[pi] == 2 { net = .init(mapped[states[i].next.rawValue]) }
                    else { net = try constant(match.bindings[pi] == 1, context: &context) }
                    instances[i].pins[pi] = net
                }
            }
            var pinCount = 0
            for instance in instances { pinCount = try MappingArithmetic.sum(pinCount, instance.pins.count) }
            var builder = try MappedGateBuilder(library: library, capacity: .init(nets: nets.count, instances: instances.count,
                pinConnections: pinCount, ports: ports.count, portBits: bits.count), context: &context)
            for net in nets { _ = try builder.addNet(net, context: &context) }
            for instance in instances {
                _ = try builder.addInstance(id: instance.id, cell: instance.cell, pinNets: instance.pins,
                    stateID: instance.stateID, initialValue: instance.initial, origin: instance.origin, context: &context)
            }
            for i in ports.indices {
                var bindings: [MappedNetIndex] = []; bindings.reserveCapacity(ports[i].bits.count)
                for offset in ports[i].bits { try context.charge(.workUnits); bindings.append(.init(mapped[bits[offset].rawValue])) }
                try builder.addPort(id: ports[i].id, direction: ports[i].direction == .input ? .input : .output,
                    nets: bindings, context: &context)
            }
            return try builder.finish(context: &context)
        }
    }
}
