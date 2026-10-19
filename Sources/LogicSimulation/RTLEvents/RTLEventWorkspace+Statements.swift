import LogicIR
import LogicKernelCore

extension RTLEventWorkspace {
    func execute(process: Int, context: inout LogicKernelContext) throws(LogicKernelError) {
        try plan.design.withProgram { signals, statements, children, items, matches, _, processes throws(LogicKernelError) in
            statementStack.removeAll(keepingCapacity: true)
            statementStack.append(processes[process].body.rawValue)
            while let index = statementStack.popLast() {
                try context.charge(.workUnits)
                if index == -1 { frozenDepth -= 1; try invalidateExpressions(); continue }
                switch statements[index].operation {
                case .empty: break
                case .assignment(let target, let selection, let value, let timing):
                    let evaluated = try expression(value, context: &context)
                    if case .nonBlocking = timing {
                        let source = try signals[target.rawValue].valueDomain == .twoState
                            ? evaluated.convertedToTwoState(context: &context) : evaluated
                        for bit in selection {
                            try context.charge(.workUnits)
                            let location = plan.offsets[target.rawValue] + bit
                            pending[location] = try source.bit(at: bit - selection.lowerBound)
                            pendingMask[location] = true
                        }
                    } else { try assign(target.rawValue, selection: selection, value: evaluated, process: process, context: &context) }
                case .block(let range):
                    for position in range.reversed() { statementStack.append(children[position].rawValue) }
                case .assignmentGroup(let range):
                    if frozenDepth == 0 {
                        // One generation freezes data and dynamic address predicates
                        // against the same pre-write environment for the whole group.
                        for root in 0..<plan.design.expressionCount { _ = try expression(.init(root), context: &context) }
                    }
                    frozenDepth += 1
                    statementStack.append(-1)
                    for position in range.reversed() { statementStack.append(children[position].rawValue) }
                case .conditional(let condition, let yes, let no):
                    if try expression(condition, context: &context).logicalFourState(context: &context) == .one {
                        statementStack.append(yes.rawValue)
                    } else if let no { statementStack.append(no.rawValue) }
                case .caseStatement(let selector, let range, let fallback):
                    let selected = try expression(selector, context: &context)
                    var chosen = fallback
                    var matched = false
                    for position in range {
                        for match in items[position].matches {
                            try context.charge(.workUnits)
                            let candidate = try expression(matches[match], context: &context)
                            if try selected.equalsFourState(candidate, caseEquality: true, context: &context) == .one {
                                chosen = items[position].body; matched = true; break
                            }
                        }
                        if matched { break }
                    }
                    if let chosen { statementStack.append(chosen.rawValue) }
                }
            }
        }
    }
    func assign(_ target: Int, selection: Range<Int>, value: borrowing LogicFourStateVector,
                process: Int, context: inout LogicKernelContext) throws(LogicKernelError) {
        let previous = values[target]
        let domain = plan.design.withProgram { signals, _, _, _, _, _, _ in signals[target].valueDomain }
        let assigned = try domain == .twoState ? value.convertedToTwoState(context: &context) : copy value
        for bit in selection {
            try context.charge(.workUnits)
            if try previous.bit(at: bit) != assigned.bit(at: bit - selection.lowerBound) {
                try changed(bit: plan.offsets[target] + bit, executing: process, context: &context)
            }
        }
        if selection == 0..<previous.width.value { values[target] = assigned }
        else {
            let bytes = UInt64(previous.width.wordCount).multipliedReportingOverflow(by: 16)
            guard !bytes.overflow else { throw .invalidInput("Partial assignment payload overflows") }
            _ = try context.reserveStorage(byteCount: bytes.partialValue)
            var ones = [UInt64](repeating: 0, count: previous.width.wordCount)
            var unknowns = [UInt64](repeating: 0, count: previous.width.wordCount)
            for bit in 0..<previous.width.value {
                try context.charge(.workUnits)
                let digit = try (selection.contains(bit) ? assigned.bit(at: bit - selection.lowerBound) : previous.bit(at: bit)).rawValue
                ones[bit / 64] |= UInt64(digit & 1) << (bit % 64)
                unknowns[bit / 64] |= UInt64((digit >> 1) & 1) << (bit % 64)
            }
            values[target] = try .init(width: previous.width, valueWords: ones, unknownWords: unknowns)
        }
        try invalidateExpressions()
    }
    func commitNBA(context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        var committed = false
        for signal in values.indices {
            let start = plan.offsets[signal]; let end = plan.offsets[signal + 1]
            var scheduled = false
            for bit in start..<end {
                try context.charge(.workUnits)
                if pendingMask[bit] { scheduled = true; break }
            }
            if !scheduled { continue }
            committed = true
            let previous = values[signal]
            _ = try context.reserveStorage(byteCount: UInt64(previous.width.wordCount) * 16)
            var ones = [UInt64](repeating: 0, count: previous.width.wordCount)
            var unknowns = [UInt64](repeating: 0, count: previous.width.wordCount)
            for bit in start..<end {
                try context.charge(.workUnits)
                let local = bit - start
                let digit = try pendingMask[bit] ? pending[bit] : previous.bit(at: local)
                if try digit != previous.bit(at: local) { try changed(bit: bit, executing: -1, context: &context) }
                pendingMask[bit] = false
                ones[local / 64] |= UInt64(digit.rawValue & 1) << (local % 64)
                unknowns[local / 64] |= UInt64((digit.rawValue >> 1) & 1) << (local % 64)
            }
            values[signal] = try .init(width: previous.width, valueWords: ones, unknownWords: unknowns)
        }
        if committed { try invalidateExpressions() }
        return committed
    }
}
