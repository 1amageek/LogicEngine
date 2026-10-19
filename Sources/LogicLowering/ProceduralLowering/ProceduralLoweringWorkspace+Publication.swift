import CircuiteFoundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension ProceduralLoweringWorkspace {
    mutating func publish(context: inout LogicKernelContext) throws(LogicKernelError) -> WordLogicDesign {
        try finalizeStateOrder(context: &context)
        try verifyRaces(context: &context)
        for _ in nodes.indices {
            try context.charge(.workUnits)
            try mapping.append(-1, receipt: &receipt, bytes: &bytes, context: &context)
        }
        for index in ports.indices { try retain(ports[index].value.rawValue, context: &context) }
        for index in states.indices {
            guard let state = states[index] else { throw .invalidModel("Unresolved retained RTL state") }
            try retain(state.next.rawValue, context: &context)
            switch state.control {
            case .flipFlop(let clock, _, let enable, let reset):
                try retain(clock.rawValue, context: &context)
                if let enable { try retain(enable.rawValue, context: &context) }
                if let reset { try retain(reset.signal.rawValue, context: &context) }
            case .latch(let gate, _, let reset):
                try retain(gate.rawValue, context: &context)
                if let reset { try retain(reset.signal.rawValue, context: &context) }
            }
        }
        for index in bits.indices where bits[index].state >= 0 { try retain(bits[index].proxy, context: &context) }
        var count = 0; var edgeCount = 0
        for index in nodes.indices where mapping[index] >= 0 {
            try context.charge(.workUnits)
            mapping[index] = count; count += 1
            let increment = nodes[index].alias == nil ? nodes[index].operands.count : 1
            let sum = edgeCount.addingReportingOverflow(increment)
            guard !sum.overflow else { throw .resourceLimit(resource: .edges, limit: context.limits[.edges], requested: nil) }
            edgeCount = sum.partialValue
        }
        var builder = try WordLogicBuilder(capacity: WordGraphCapacity(nodes: count, operands: edgeCount,
            ports: ports.count, states: states.count), context: &context)
        for index in nodes.indices where mapping[index] >= 0 {
            try context.charge(.workUnits)
            let source = nodes[index]
            publicationInputs.truncate(0)
            let operation: WordLogicOperation
            if let alias = source.alias {
                operation = .compute(.bitcast)
                try publicationInputs.append(WordNodeIndex(mapping[alias]), receipt: &receipt, bytes: &bytes, context: &context)
            } else {
                guard let resolved = source.operation else { throw failure("Observed RTL storage has no binary driver or initial value", origin: source.origin) }
                operation = resolved
                for offset in source.operands {
                    try context.charge(.workUnits)
                    try publicationInputs.append(WordNodeIndex(mapping[operands[offset]]), receipt: &receipt, bytes: &bytes, context: &context)
                }
            }
            _ = try builder.addNode(id: entity(index), type: source.type,
                operation: operation, inputs: publicationInputs.values, origin: source.origin, context: &context)
        }
        for index in ports.indices {
            let port = ports[index]
            try builder.addPort(WordLogicPort(id: port.id, direction: port.direction,
                value: WordNodeIndex(mapping[port.value.rawValue])), context: &context)
        }
        for index in states.indices {
            let state = states[index]!
            let control: WordStateControl
            func remapReset(_ reset: WordReset?) -> WordReset? {
                reset.map { WordReset(signal: WordNodeIndex(mapping[$0.signal.rawValue]), activeHigh: $0.activeHigh,
                    value: $0.value, kind: $0.kind) }
            }
            switch state.control {
            case .flipFlop(let clock, let edge, let enable, let reset):
                control = .flipFlop(clock: WordNodeIndex(mapping[clock.rawValue]), edge: edge,
                    enable: enable.map { WordNodeIndex(mapping[$0.rawValue]) }, reset: remapReset(reset))
            case .latch(let gate, let high, let reset):
                control = .latch(gate: WordNodeIndex(mapping[gate.rawValue]), activeHigh: high, reset: remapReset(reset))
            }
            _ = try builder.addState(WordLogicState(id: try entity(index), next: WordNodeIndex(mapping[state.next.rawValue]),
                control: control, initialValue: state.initialValue, origin: state.origin), context: &context)
        }
        return try builder.finish(context: &context)
    }

    mutating func retain(_ root: Int, context: inout LogicKernelContext) throws(LogicKernelError) {
        if mapping[root] >= 0 { return }
        mapping[root] = 0
        try pending.append(root, receipt: &receipt, bytes: &bytes, context: &context)
        while let index = pending.popLast() {
            try context.charge(.workUnits)
            let node = nodes[index]
            if let alias = node.alias {
                if mapping[alias] < 0 {
                    mapping[alias] = 0
                    try pending.append(alias, receipt: &receipt, bytes: &bytes, context: &context)
                }
            } else {
                guard node.operation != nil else { throw failure("Observed RTL storage has no binary driver or initial value", origin: node.origin) }
                for offset in node.operands {
                    try context.charge(.workUnits)
                    let input = operands[offset]
                    if mapping[input] < 0 {
                        mapping[input] = 0
                        try pending.append(input, receipt: &receipt, bytes: &bytes, context: &context)
                    }
                }
            }
        }
    }
}
