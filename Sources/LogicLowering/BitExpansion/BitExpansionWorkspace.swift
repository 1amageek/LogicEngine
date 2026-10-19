import CircuiteFoundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
internal struct BitExpansionWorkspace: ~Copyable {
    private var builder: BitLogicBuilder
    private var offsets: [Int]
    private var stateOffsets: [Int]
    private var bindings: [BitNodeIndex]
    private var scratch: [BitNodeIndex]
    private var inputs: [BitNodeIndex] = []
    private var portBuffer: [BitNodeIndex] = []
    private var nodeCount = 0
    private var zero = BitNodeIndex(0)
    private var one = BitNodeIndex(0)

    init(plan: BitExpansionPlan, nodeCount: Int, stateCount: Int, builder: consuming BitLogicBuilder) {
        self.builder = builder
        offsets = [Int](repeating: 0, count: nodeCount + 1)
        stateOffsets = [Int](repeating: 0, count: stateCount + 1)
        bindings = [BitNodeIndex](repeating: BitNodeIndex(0), count: plan.bitCount)
        scratch = [BitNodeIndex](repeating: BitNodeIndex(0), count: plan.maximumWidth * 2)
        inputs.reserveCapacity(3); portBuffer.reserveCapacity(plan.maximumWidth)
    }

    mutating func expand(nodes: borrowing Span<WordLogicNode>, operands: borrowing Span<WordNodeIndex>,
                         ports: borrowing Span<WordLogicPort>, states: borrowing Span<WordLogicState>,
                         order: borrowing Span<WordNodeIndex>, context: inout LogicKernelContext) throws(LogicKernelError) {
        // All fields are initialized before fallible work touches this exclusive owner.
        for index in nodes.indices {
            try context.charge(.workUnits); offsets[index + 1] = offsets[index] + nodes[index].type.width.value
        }
        for index in states.indices {
            try context.charge(.workUnits)
            stateOffsets[index + 1] = stateOffsets[index] + nodes[states[index].next.rawValue].type.width.value
        }
        zero = try emit(.constant(false), context: &context)
        one = try emit(.constant(true), context: &context)
        for ordinal in order.indices {
            try context.charge(.workUnits)
            let index = order[ordinal].rawValue; let node = nodes[index]
            let width = node.type.width.value; let base = offsets[index]
            switch node.operation {
            case .input:
                for bit in 0..<width { bindings[base + bit] = try emit(.input, origin: node.origin, context: &context) }
            case .constant(let value):
                for bit in 0..<width {
                    bindings[base + bit] = try emit(.constant(try value.bit(at: bit) == .one), origin: node.origin, context: &context)
                }
            case .state(let state):
                for bit in 0..<width {
                    bindings[base + bit] = try emit(.state(BitStateIndex(stateOffsets[state.rawValue] + bit)),
                                                   origin: node.origin, context: &context)
                }
            case .compute(let opcode):
                try compute(opcode, node: node, base: base, nodes: nodes, operands: operands, context: &context)
            }
        }
        for index in ports.indices {
            let port = ports[index]
            portBuffer.removeAll(keepingCapacity: true)
            for bit in offsets[port.value.rawValue]..<offsets[port.value.rawValue + 1] {
                try context.charge(.workUnits); portBuffer.append(bindings[bit])
            }
            try builder.addPort(id: port.id, direction: port.direction, bits: portBuffer, context: &context)
        }
        for index in states.indices {
            let state = states[index]; let nextBase = offsets[state.next.rawValue]
            let width = nodes[state.next.rawValue].type.width.value
            for bit in 0..<width {
                try context.charge(.workUnits)
                let control: BitStateControl
                switch state.control {
                case .flipFlop(let clock, let edge, let enable, let reset):
                    control = .flipFlop(clock: binding(clock), edge: edge,
                                        enable: enable.map { binding($0) }, reset: try bitReset(reset, bit: bit))
                case .latch(let gate, let activeHigh, let reset):
                    control = .latch(gate: binding(gate), activeHigh: activeHigh, reset: try bitReset(reset, bit: bit))
                }
                let initial: Bool?
                if let value = state.initialValue { initial = try value.bit(at: bit) == .one } else { initial = nil }
                let result = try builder.addState(BitLogicState(id: entity(stateOffsets[index] + bit),
                    next: bindings[nextBase + bit], control: control, initialValue: initial, origin: state.origin), context: &context)
                guard result.rawValue == stateOffsets[index] + bit else { throw .invalidModel("State expansion order changed") }
            }
        }
    }

    private borrowing func bitReset(_ reset: WordReset?, bit: Int) throws(LogicKernelError) -> BitReset? {
        guard let reset else { return nil }
        return BitReset(signal: binding(reset.signal), activeHigh: reset.activeHigh,
                        value: try reset.value.bit(at: bit) == .one, kind: reset.kind)
    }

    private borrowing func binding(_ word: WordNodeIndex, _ bit: Int = 0) -> BitNodeIndex {
        bindings[offsets[word.rawValue] + bit]
    }

    private mutating func compute(_ opcode: WordLogicOpcode, node: WordLogicNode, base: Int,
                                  nodes: borrowing Span<WordLogicNode>, operands: borrowing Span<WordNodeIndex>,
                                  context: inout LogicKernelContext) throws(LogicKernelError) {
        let width = node.type.width.value; let origin = node.origin
        let first = operands[node.operands.lowerBound]
        let firstWidth = nodes[first.rawValue].type.width.value
        switch opcode {
        case .bitcast, .zeroExtend, .signExtend, .slice:
            let offset: Int
            if case .slice(let selected) = opcode { offset = selected } else { offset = 0 }
            for bit in 0..<width {
                let source: BitNodeIndex
                if bit + offset < firstWidth { source = binding(first, bit + offset) }
                else if opcode == .signExtend { source = binding(first, firstWidth - 1) }
                else { source = zero }
                bindings[base + bit] = try emit(.buffer, source, origin: origin, context: &context)
            }
        case .concatenate:
            var output = base
            for operandOffset in node.operands.reversed() {
                let word = operands[operandOffset]
                for bit in 0..<nodes[word.rawValue].type.width.value {
                    bindings[output] = try emit(.buffer, binding(word, bit), origin: origin, context: &context)
                    output += 1
                }
            }
        case .invert:
            for bit in 0..<width { bindings[base + bit] = try emit(.invert, binding(first, bit), origin: origin, context: &context) }
        case .and, .or, .xor:
            let second = operands[node.operands.lowerBound + 1]
            let operation: BitOperation = opcode == .and ? .and : opcode == .or ? .or : .xor
            for bit in 0..<width {
                bindings[base + bit] = try emit(operation, binding(first, bit), binding(second, bit), origin: origin, context: &context)
            }
        case .add, .subtract, .negate:
            var carry = opcode == .add ? zero : one
            for bit in 0..<width {
                let a: BitNodeIndex; let b: BitNodeIndex
                if opcode == .negate {
                    a = zero; b = try emit(.invert, binding(first, bit), origin: origin, context: &context)
                } else {
                    a = binding(first, bit)
                    let value = binding(operands[node.operands.lowerBound + 1], bit)
                    b = opcode == .subtract ? try emit(.invert, value, origin: origin, context: &context) : value
                }
                let result = try add(a, b, carry, origin: origin, context: &context)
                bindings[base + bit] = result.sum; carry = result.carry
            }
        case .multiply:
            let second = operands[node.operands.lowerBound + 1]
            for bit in 0..<width { bindings[base + bit] = zero }
            for row in 0..<width {
                var carry = zero
                for bit in row..<width {
                    let product = try emit(.and, binding(first, bit - row), binding(second, row), origin: origin, context: &context)
                    let result = try add(bindings[base + bit], product, carry, origin: origin, context: &context)
                    bindings[base + bit] = result.sum; carry = result.carry
                }
            }
        case .equal:
            let second = operands[node.operands.lowerBound + 1]; var different = zero
            for bit in 0..<firstWidth {
                let difference = try emit(.xor, binding(first, bit), binding(second, bit), origin: origin, context: &context)
                different = try emit(.or, different, difference, origin: origin, context: &context)
            }
            bindings[base] = try emit(.invert, different, origin: origin, context: &context)
        case .lessThan:
            let second = operands[node.operands.lowerBound + 1]; var less = zero
            for bit in 0..<firstWidth {
                let a = binding(first, bit); let b = binding(second, bit)
                let notA = try emit(.invert, a, origin: origin, context: &context)
                let local = try emit(.and, notA, b, origin: origin, context: &context)
                let difference = try emit(.xor, a, b, origin: origin, context: &context)
                // If this bit differs it decides; otherwise retain lower-bit ordering.
                less = try emit(.select, difference, local, less, origin: origin, context: &context)
            }
            if nodes[first.rawValue].type.isSigned {
                let signA = binding(first, firstWidth - 1); let signB = binding(second, firstWidth - 1)
                let difference = try emit(.xor, signA, signB, origin: origin, context: &context)
                less = try emit(.select, difference, signA, less, origin: origin, context: &context)
            }
            bindings[base] = less
        case .logicalNot, .logicalAnd, .logicalOr, .reduceAnd, .reduceOr, .reduceXor:
            let operation: BitOperation = opcode == .reduceAnd ? .and : opcode == .reduceXor ? .xor : .or
            var reduced = opcode == .reduceAnd ? one : zero
            for bit in 0..<firstWidth {
                reduced = try emit(operation, reduced, binding(first, bit), origin: origin, context: &context)
            }
            if opcode == .logicalNot { reduced = try emit(.invert, reduced, origin: origin, context: &context) }
            if opcode == .logicalAnd || opcode == .logicalOr {
                let second = operands[node.operands.lowerBound + 1]; var other = zero
                for bit in 0..<nodes[second.rawValue].type.width.value {
                    other = try emit(.or, other, binding(second, bit), origin: origin, context: &context)
                }
                reduced = try emit(opcode == .logicalAnd ? .and : .or, reduced, other, origin: origin, context: &context)
            }
            bindings[base] = reduced
        case .select:
            let ifTrue = operands[node.operands.lowerBound + 1]; let ifFalse = operands[node.operands.lowerBound + 2]
            for bit in 0..<width {
                bindings[base + bit] = try emit(.select, binding(first), binding(ifTrue, bit), binding(ifFalse, bit),
                                              origin: origin, context: &context)
            }
        case .shiftLeft, .shiftRight:
            let amount = operands[node.operands.lowerBound + 1]
            let amountWidth = nodes[amount.rawValue].type.width.value
            let isLeft = opcode == .shiftLeft
            let fill: BitNodeIndex
            if case .shiftRight(arithmetic: true) = opcode, nodes[first.rawValue].type.isSigned {
                fill = binding(first, width - 1)
            } else { fill = zero }
            for bit in 0..<width { scratch[bit] = binding(first, bit) }
            var current = 0; var next = width; var stage = 0; var distance = 1
            while distance < width && stage < amountWidth {
                for bit in 0..<width {
                    let source: BitNodeIndex
                    if isLeft { source = bit >= distance ? scratch[current + bit - distance] : fill }
                    else { source = distance < width - bit ? scratch[current + bit + distance] : fill }
                    scratch[next + bit] = try emit(.select, binding(amount, stage), source, scratch[current + bit],
                                                  origin: origin, context: &context)
                }
                swap(&current, &next); stage += 1
                if distance > Int.max / 2 { break }
                distance *= 2
            }
            var oversized = zero
            for bit in stage..<amountWidth {
                oversized = try emit(.or, oversized, binding(amount, bit), origin: origin, context: &context)
            }
            for bit in 0..<width {
                bindings[base + bit] = try emit(.select, oversized, fill, scratch[current + bit], origin: origin, context: &context)
            }
        }
    }

    private mutating func add(_ a: BitNodeIndex, _ b: BitNodeIndex, _ carry: BitNodeIndex,
                              origin: LogicKernelSourceRange?, context: inout LogicKernelContext)
        throws(LogicKernelError) -> (sum: BitNodeIndex, carry: BitNodeIndex) {
        let different = try emit(.xor, a, b, origin: origin, context: &context)
        let sum = try emit(.xor, different, carry, origin: origin, context: &context)
        let generated = try emit(.and, a, b, origin: origin, context: &context)
        let propagated = try emit(.and, different, carry, origin: origin, context: &context)
        return (sum, try emit(.or, generated, propagated, origin: origin, context: &context))
    }

    private mutating func emit(_ operation: BitOperation, _ first: BitNodeIndex? = nil,
                               _ second: BitNodeIndex? = nil, _ third: BitNodeIndex? = nil,
                               origin: LogicKernelSourceRange? = nil, context: inout LogicKernelContext)
        throws(LogicKernelError) -> BitNodeIndex {
        try context.charge(.workUnits); try context.charge(.expansion)
        inputs.removeAll(keepingCapacity: true)
        if let first { inputs.append(first) }; if let second { inputs.append(second) }; if let third { inputs.append(third) }
        let result = try builder.addNode(id: entity(nodeCount), operation: operation, inputs: inputs, origin: origin, context: &context)
        nodeCount += 1
        return result
    }

    private borrowing func entity(_ ordinal: Int) throws(LogicKernelError) -> DesignEntityID {
        do { return try DesignEntityID(rawValue: UInt64(ordinal) + 1) }
        catch { throw .invalidModel("Generated entity identity is invalid") }
    }

    consuming func finish(context: inout LogicKernelContext) throws(LogicKernelError) -> BitLogicDesign {
        try builder.finish(context: &context)
    }
}
