import CircuiteFoundation
import LogicIR
import LogicKernelCore

internal enum MappingControlExpansion {
    static func expand(_ source: borrowing BitLogicDesign, policy: borrowing LogicMappingPolicy,
                       context: inout LogicKernelContext) throws(LogicKernelError) -> MappingGraph {
        let count = try MappingArithmetic.sum(MappingArithmetic.product(source.nodeCount, 8), MappingArithmetic.product(source.stateCount, 15))
        let identities = try MappingArithmetic.sum(count, MappingArithmetic.sum(source.portCount, source.stateCount))
        let firstID = policy.firstEntityID.rawValue
        return try source.withTables { nodes, operands, ports, bits, states, sourceOrder throws(LogicKernelError) in
            var ids = MappingIdentityAllocator(next: firstID, used: [])
            ids.used.reserveCapacity(identities)
            for i in nodes.indices { try context.charge(.workUnits); ids.used.insert(nodes[i].id) }
            for i in ports.indices { try context.charge(.workUnits); ids.used.insert(ports[i].id) }
            for i in states.indices { try context.charge(.workUnits); ids.used.insert(states[i].id) }
            var drafts: [MappingLogicDraft] = []; drafts.reserveCapacity(count)
            var stateNodes = [BitNodeIndex](repeating: .init(0), count: states.count)
            for i in nodes.indices {
                try context.charge(.workUnits)
                var inputs: [BitNodeIndex] = []; inputs.reserveCapacity(3)
                for index in nodes[i].operands { inputs.append(operands[index]) }
                drafts.append(.init(id: nodes[i].id, operation: nodes[i].operation, inputs: inputs, origin: nodes[i].origin))
                if case .state(let s) = nodes[i].operation { stateNodes[s.rawValue] = .init(i) }
            }
            var order: [BitNodeIndex] = []; order.reserveCapacity(count)
            func append(_ op: BitOperation, _ inputs: [BitNodeIndex], _ origin: LogicKernelSourceRange?)
                throws(LogicKernelError) -> BitNodeIndex {
                try context.charge(.workUnits)
                let index = BitNodeIndex(drafts.count); order.append(index)
                drafts.append(.init(id: try ids.allocate(context: &context), operation: op, inputs: inputs, origin: origin)); return index
            }
            func either(_ a: BitNodeIndex, _ b: BitNodeIndex, _ origin: LogicKernelSourceRange?) throws(LogicKernelError) -> BitNodeIndex {
                let na = try append(.invert, [a], origin); let nb = try append(.invert, [b], origin)
                let both = try append(.and, [na, nb], origin); return try append(.invert, [both], origin)
            }
            func select(_ s: BitNodeIndex, _ t: BitNodeIndex, _ f: BitNodeIndex, _ origin: LogicKernelSourceRange?) throws(LogicKernelError) -> BitNodeIndex {
                let ns = try append(.invert, [s], origin)
                let take = try append(.and, [s,t], origin); let hold = try append(.and, [ns,f], origin)
                return try either(take, hold, origin)
            }
            for position in sourceOrder.indices {
                let i = sourceOrder[position].rawValue
                try context.charge(.workUnits); let original = drafts[i]; let inputs = original.inputs
                let root: BitNodeIndex
                switch original.operation {
                case .or: root = try either(inputs[0], inputs[1], original.origin)
                case .xor:
                    let eitherValue = try either(inputs[0], inputs[1], original.origin)
                    let both = try append(.and, [inputs[0],inputs[1]], original.origin)
                    let notBoth = try append(.invert, [both], original.origin)
                    root = try append(.and, [eitherValue,notBoth], original.origin)
                case .select: root = try select(inputs[0],inputs[1],inputs[2],original.origin)
                default: order.append(.init(i)); continue
                }
                order.append(.init(i))
                drafts[i] = .init(id: original.id, operation: .buffer, inputs: [root], origin: original.origin)
            }
            var expandedStates: [BitLogicState] = []; expandedStates.reserveCapacity(states.count)
            for i in states.indices {
                try context.charge(.workUnits); let state = states[i]; var next = state.next
                let reset: BitReset?; let control: BitStateControl
                switch state.control {
                case .flipFlop(let clock, let edge, let enable, let r):
                    reset = r
                    if let enable { next = try select(enable, next, stateNodes[i], state.origin) }
                    control = .flipFlop(clock: clock, edge: edge, enable: nil, reset: r?.kind == .asynchronous ? r : nil)
                case .latch(let gate, let active, let r):
                    reset = r; control = .latch(gate: gate, activeHigh: active, reset: r?.kind == .asynchronous ? r : nil)
                }
                if let reset, reset.kind == .synchronous {
                    let value = try append(.constant(reset.value), [], state.origin)
                    next = try select(reset.signal, reset.activeHigh ? value : next, reset.activeHigh ? next : value, state.origin)
                }
                expandedStates.append(.init(id: state.id, next: next, control: control, initialValue: state.initialValue, origin: state.origin))
            }
            var retainedPorts: [BitLogicPort] = []; retainedPorts.reserveCapacity(ports.count)
            var retainedBits: [BitNodeIndex] = []; retainedBits.reserveCapacity(bits.count)
            for i in ports.indices { try context.charge(.workUnits); retainedPorts.append(ports[i]) }
            for i in bits.indices { try context.charge(.workUnits); retainedBits.append(bits[i]) }
            return MappingGraph(nodes: drafts, ports: retainedPorts, bits: retainedBits, states: expandedStates, order: order)
        }
    }
}
