import CircuiteFoundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension ProceduralLoweringWorkspace {
    mutating func lowerProcess(_ index: Int, processes: borrowing Span<RTLResolvedProcess>,
                              statements: borrowing Span<RTLResolvedStatement>, children: borrowing Span<RTLStatementIndex>,
                              items: borrowing Span<RTLResolvedCaseItem>, matches: borrowing Span<RTLExpressionIndex>,
                              expressions: borrowing Span<RTLResolvedExpression>, expressionOperands: borrowing Span<RTLExpressionIndex>,
                              context: inout LogicKernelContext) throws(LogicKernelError) {
        let process = processes[index]
        var body = process.body.rawValue
        var clock: Int?
        var reset: RTLResolvedReset?
        var resetBody: Int?
        if case .flipFlop(let sourceClock, _, let asynchronousReset) = process.control {
            clock = try evaluate(sourceClock.rawValue, expressions: expressions, inputs: expressionOperands,
                                 current: false, context: &context)
            reset = asynchronousReset
            if let reset {
                while case .block(let range) = statements[body].operation, range.count == 1 {
                    try context.charge(.workUnits); body = children[range.lowerBound].rawValue
                }
                guard case .conditional(let test, let yes, let no) = statements[body].operation,
                      let polarity = try resetPolarity(test.rawValue, reset: reset.signal.rawValue,
                                                   expressions: expressions, inputs: expressionOperands, context: &context) else {
                    throw failure("Asynchronous reset requires a dominant polarity-matched branch", origin: process.origin)
                }
                if polarity == reset.activeHigh {
                    resetBody = yes.rawValue; body = no?.rawValue ?? -1
                } else {
                    guard let no else { throw failure("Asynchronous reset branch is missing", origin: process.origin) }
                    resetBody = no.rawValue; body = yes.rawValue
                }
            }
        }
        var resetSignal: Int?
        if let reset, let resetBody {
            resetSignal = try evaluate(reset.signal.rawValue, expressions: expressions, inputs: expressionOperands,
                                       current: false, context: &context)
            resetOverride = (reset.signal.rawValue, reset.activeHigh ? 1 : 0)
            try execute(resetBody, statements: statements, children: children, items: items, matches: matches,
                        expressions: expressions, expressionOperands: expressionOperands, context: &context)
            for location in bits.indices where bits[location].writer == index {
                try context.charge(.workUnits)
                let record = bits[location].record
                let value = try select(record.nbaEnable, record.nbaData, record.blockingData, context: &context)
                guard record.complete, let constant = booleanConstant(value) else {
                    throw failure("Asynchronous reset must assign every retained state bit a binary constant", origin: process.origin)
                }
                // The pending state's reset value is retained separately from the
                // normal process environment; no asynchronous MUX is introduced.
                let vector = try LogicFourStateVector(repeating: constant ? .one : .zero, width: scalar.width, context: &context)
                bits[location].reset = WordReset(signal: WordNodeIndex(resetSignal!), activeHigh: reset.activeHigh,
                    value: vector, kind: .asynchronous)
            }
            try clearEnvironment(process: index, context: &context)
            resetOverride = (reset.signal.rawValue, reset.activeHigh ? 0 : 1)
        }
        if body >= 0 {
            try execute(body, statements: statements, children: children, items: items, matches: matches,
                        expressions: expressions, expressionOperands: expressionOperands, context: &context)
        }
        resetOverride = nil
        for signalIndex in signals.indices {
            let signal = signals[signalIndex]
            for offset in 0..<signal.type.width.value {
                try context.charge(.workUnits)
                let location = signal.offset + offset
                guard bits[location].writer == index else { continue }
                let record = bits[location].record
                let data = try select(record.nbaEnable, record.nbaData, record.blockingData,
                                      origin: process.origin, context: &context)
                let enable = record.complete ? 1 : try compute(.or, type: scalar, a: record.blockingEnable,
                    b: record.nbaEnable, origin: process.origin, context: &context)
                switch process.control {
                case .continuous, .combinational:
                    guard record.complete else { throw failure("Combinational variable bit is not assigned on every path", origin: process.origin) }
                    nodes[bits[location].proxy].alias = data
                case .levelSensitive:
                    if record.complete { nodes[bits[location].proxy].alias = data }
                    else {
                        try bindState(location, signal: signal, offset: offset, data: data,
                            control: latchControl(enable), origin: process.origin, context: &context)
                    }
                case .flipFlop(_, let edge, _):
                    try bindState(location, signal: signal, offset: offset, data: data,
                        control: .flipFlop(clock: WordNodeIndex(clock!), edge: edge,
                            enable: enable == 1 ? nil : WordNodeIndex(enable), reset: bits[location].reset),
                        origin: process.origin, context: &context)
                case .latch:
                    try bindState(location, signal: signal, offset: offset, data: data,
                        control: latchControl(enable), origin: process.origin, context: &context)
                }
            }
        }
        try clearEnvironment(process: index, context: &context)
    }

    func latchControl(_ enable: Int) -> WordStateControl {
        if case .compute(.logicalNot) = nodes[enable].operation {
            return .latch(gate: WordNodeIndex(operands[nodes[enable].operands.lowerBound]), activeHigh: false, reset: nil)
        }
        return .latch(gate: WordNodeIndex(enable), activeHigh: true, reset: nil)
    }

    mutating func bindState(_ location: Int, signal: Signal, offset: Int, data: Int,
                           control: WordStateControl, origin: LogicKernelSourceRange?,
                           context: inout LogicKernelContext) throws(LogicKernelError) {
        if bits[location].state < 0 {
            try context.require(.states, amount: UInt64(states.count) + 1)
            bits[location].state = states.count
            nodes[bits[location].proxy].operation = .state(WordStateIndex(states.count))
            try states.append(nil, receipt: &receipt, bytes: &bytes, context: &context)
            try stateBits.append(location, receipt: &receipt, bytes: &bytes, context: &context)
        }
        let stateIndex = bits[location].state
        let initial: LogicFourStateVector?
        if let source = signal.initial {
            guard source.isTwoState else { throw failure("Retained synthesis state has an X/Z initial value", origin: signal.origin) }
            initial = try LogicFourStateVector(repeating: source.bit(at: offset), width: scalar.width, context: &context)
        } else { initial = nil }
        states[stateIndex] = WordLogicState(id: try entity(stateIndex), next: WordNodeIndex(data), control: control,
            initialValue: initial, origin: origin ?? signal.origin)
    }

    mutating func finalizeStateOrder(context: inout LogicKernelContext) throws(LogicKernelError) {
        var next = 0
        for location in bits.indices {
            try context.charge(.workUnits)
            let old = bits[location].state
            guard old >= 0 else { continue }
            if old != next {
                let displaced = stateBits[next]
                let state = states[old]; states[old] = states[next]; states[next] = state
                stateBits[old] = displaced; stateBits[next] = location
                bits[displaced].state = old; bits[location].state = next
                nodes[bits[displaced].proxy].operation = .state(WordStateIndex(old))
                nodes[bits[location].proxy].operation = .state(WordStateIndex(next))
            }
            next += 1
        }
    }

    mutating func clearEnvironment(process: Int, context: inout LogicKernelContext) throws(LogicKernelError) {
        for index in bits.indices where bits[index].writer == process {
            try context.charge(.workUnits)
            bits[index].record = Record(current: bits[index].proxy)
        }
        journal.truncate(0)
    }

    func resetPolarity(_ condition: Int, reset: Int, expressions: borrowing Span<RTLResolvedExpression>,
                       inputs: borrowing Span<RTLExpressionIndex>, context: inout LogicKernelContext) throws(LogicKernelError) -> Bool? {
        var expression = condition; var positive = true
        while true {
            try context.charge(.workUnits)
            if expression == reset { return positive }
            let source = expressions[expression]
            if case .read(let signal) = source.operation, case .read(let other) = expressions[reset].operation,
               signal == other { return positive }
            switch source.operation {
            case .compute(.logicalNot), .compute(.invert):
                positive.toggle(); expression = inputs[source.operands.lowerBound].rawValue
            case .compute(.bitcast): expression = inputs[source.operands.lowerBound].rawValue
            case .compute(.equal), .caseEqual:
                let left = inputs[source.operands.lowerBound].rawValue
                let right = inputs[source.operands.lowerBound + 1].rawValue
                let constant: LogicFourStateVector
                if case .constant(let value) = expressions[left].operation { constant = value; expression = right }
                else if case .constant(let value) = expressions[right].operation { constant = value; expression = left }
                else { return nil }
                guard constant.width.value == 1, constant.isTwoState else { return nil }
                if try constant.bit(at: 0) == .zero { positive.toggle() }
            default: return nil
            }
        }
    }
}
