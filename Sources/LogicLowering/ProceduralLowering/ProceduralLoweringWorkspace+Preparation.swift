import CircuiteFoundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension ProceduralLoweringWorkspace {
    mutating func prepare(_ source: borrowing Span<RTLResolvedSignal>, expressions: borrowing Span<RTLResolvedExpression>,
                          statements: borrowing Span<RTLResolvedStatement>, children: borrowing Span<RTLStatementIndex>,
                          items: borrowing Span<RTLResolvedCaseItem>, processes: borrowing Span<RTLResolvedProcess>,
                          context: inout LogicKernelContext) throws(LogicKernelError) {
        for bit: LogicBit in [.zero, .one] {
            let value = try LogicFourStateVector(repeating: bit, width: scalar.width, context: &context)
            _ = try emit(type: scalar, operation: .constant(value), context: &context)
        }
        for index in source.indices {
            let signal = source[index]; let width = signal.type.width.value
            try context.observeBitWidth(UInt64(width)); try context.charge(.expansion, amount: UInt64(width))
            let count = bits.count.addingReportingOverflow(width)
            guard !count.overflow else {
                throw .resourceLimit(resource: .expansion, limit: context.limits[.expansion], requested: nil)
            }
            try bits.reserve(count.partialValue, receipt: &receipt, bytes: &bytes, context: &context)
            let initial: LogicFourStateVector?
            if let specified = signal.initialValue { initial = specified }
            else if signal.valueDomain == .twoState {
                initial = try .init(repeating: signal.defaultInitialBit, width: signal.type.width, context: &context)
            } else { initial = nil }
            try signals.append(Signal(offset: bits.count, type: signal.type, initial: initial,
                origin: signal.origin), receipt: &receipt, bytes: &bytes, context: &context)
            for _ in 0..<width {
                try context.charge(.workUnits)
                try bits.append(BitSlot(), receipt: &receipt, bytes: &bytes, context: &context)
            }
        }
        for _ in expressions.indices {
            try context.charge(.workUnits)
            try cached.append(CachedExpression(), receipt: &receipt, bytes: &bytes, context: &context)
            try assignmentSamples.append(CachedExpression(), receipt: &receipt, bytes: &bytes, context: &context)
        }
        // Publication has already established single-writer and acyclic statement
        // references. This traversal determines lowering ownership, not revalidation.
        for process in processes.indices {
            try pending.append(processes[process].body.rawValue, receipt: &receipt, bytes: &bytes, context: &context)
            while let statement = pending.popLast() {
                try context.charge(.workUnits)
                switch statements[statement].operation {
                case .assignment(let signal, let selection, _, let timing):
                    for bit in selection {
                        try context.charge(.workUnits)
                        let location = signals[signal.rawValue].offset + bit
                        bits[location].writer = process
                        if case .blocking = timing, case .flipFlop = processes[process].control {
                            bits[location].blockingFFWriter = true
                        }
                    }
                case .block(let range), .assignmentGroup(let range):
                    for child in range {
                        try pending.append(children[child].rawValue, receipt: &receipt, bytes: &bytes, context: &context)
                    }
                case .conditional(_, let yes, let no):
                    try pending.append(yes.rawValue, receipt: &receipt, bytes: &bytes, context: &context)
                    if let no { try pending.append(no.rawValue, receipt: &receipt, bytes: &bytes, context: &context) }
                case .caseStatement(_, let range, let fallback):
                    for item in range {
                        try pending.append(items[item].body.rawValue, receipt: &receipt, bytes: &bytes, context: &context)
                    }
                    if let fallback { try pending.append(fallback.rawValue, receipt: &receipt, bytes: &bytes, context: &context) }
                case .empty: break
                }
            }
        }
        for index in source.indices {
            let signal = signals[index]
            if source[index].isInput {
                let input = try emit(type: signal.type, operation: .input, origin: signal.origin, context: &context)
                signals[index].input = input
                for offset in 0..<signal.type.width.value {
                    let value = try bit(input, at: offset, context: &context)
                    bits[signal.offset + offset].proxy = value
                    bits[signal.offset + offset].record.current = value
                }
                continue
            }
            for offset in 0..<signal.type.width.value {
                try context.charge(.workUnits)
                let location = signal.offset + offset; let writer = bits[location].writer
                let state: Bool
                if writer < 0 { state = false }
                else {
                    switch processes[writer].control {
                    case .flipFlop, .latch: state = true
                    case .continuous, .combinational, .levelSensitive: state = false
                    }
                }
                let operation: WordLogicOperation?
                if state {
                    try context.require(.states, amount: UInt64(states.count) + 1)
                    bits[location].state = states.count
                    operation = .state(WordStateIndex(states.count))
                    try states.append(nil, receipt: &receipt, bytes: &bytes, context: &context)
                    try stateBits.append(location, receipt: &receipt, bytes: &bytes, context: &context)
                } else { operation = nil }
                let proxy = try emit(type: scalar, operation: operation, origin: signal.origin, context: &context)
                bits[location].proxy = proxy; bits[location].record.current = proxy
                if writer < 0, let initial = signal.initial, initial.isTwoState {
                    nodes[proxy].alias = try initial.bit(at: offset) == .one ? 1 : 0
                }
            }
        }
    }
}
