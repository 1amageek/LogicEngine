import LogicIR
import LogicKernelCore

extension RTLDependencyWorkspace {
    mutating func execute(_ body: Int, statements: borrowing Span<RTLResolvedStatement>, children: borrowing Span<RTLStatementIndex>,
                          items: borrowing Span<RTLResolvedCaseItem>, matches: borrowing Span<RTLExpressionIndex>,
                          expressions: borrowing Span<RTLResolvedExpression>, operands: borrowing Span<RTLExpressionIndex>,
                          signals: borrowing Span<RTLResolvedSignal>, isFF: Bool,
                          context: inout LogicKernelContext) throws(LogicKernelError) {
        try flow.append(.visit(body), context: &context)
        while let task = flow.popLast() {
            try context.charge(.workUnits)
            switch task {
            case .endGroup: frozenDepth -= 1; try nextEpoch()
            case .branchEnd(let frame): try branchEnd(frame, items: items, context: &context)
            case .visit(let index):
                switch statements[index].operation {
                case .empty: break
                case .assignment(let target, let selection, let value, let timing):
                    assignment.truncate(0); assignmentSymbols.truncate(0)
                    for local in 0..<selection.count {
                        let root = try dependency(value.rawValue, bit: local, expressions: expressions, operands: operands, context: &context)
                        var term = try symbol(value.rawValue, bit: local, expressions: expressions, operands: operands, context: &context)
                        if signals[target.rawValue].valueDomain == .twoState {
                            term = try guards.convertedToTwoState(term, base: bitCount + 4, context: &context)
                        }
                        try assignmentSymbols.append(term, context: &context)
                        try markReads(root, context: &context); try assignment.append(root, context: &context)
                    }
                    for local in 0..<selection.count {
                        let bit = offsets[target.rawValue] + selection.lowerBound + local
                        let root = assignment[local]
                        var version = versions[bit]
                        switch timing {
                        case .blocking:
                            version.environment = root; version.environmentTag = try nextSerial(); version.symbol = assignmentSymbols[local]
                            version.blocking = root; version.blockingPossible = true
                            if !version.pendingDefinite {
                                version.finalData = version.pendingPossible ? try union(version.pending, root, context: &context) : root
                                version.finalSymbol = try mergedSymbol(condition: version.pendingGuard, a: assignmentSymbols[local], b: version.pendingSymbol, context: &context)
                                version.finalTag = try nextSerial()
                            }
                            if isFF { blockingFF[process * bitCount + bit] = true }
                        case .nonBlocking:
                            version.pending = root; version.pendingTag = try nextSerial()
                            version.pendingSymbol = assignmentSymbols[local]; version.pendingGuard = 1
                            version.finalSymbol = assignmentSymbols[local]
                            version.pendingPossible = true; version.pendingDefinite = true
                            version.finalData = root; version.finalTag = try nextSerial()
                        }
                        version.assignedDefinite = true; version.guardRoot = 1
                        try remember(bit: bit, version: version, context: &context)
                        writes[process * bitCount + bit] = true; writers[bit] = process
                    }
                    try nextEpoch()
                case .block(let range), .assignmentGroup(let range):
                    if case .assignmentGroup = statements[index].operation {
                        if frozenDepth == 0 {
                            for expression in expressions.indices {
                                for bit in 0..<expressions[expression].type.width.value {
                                    _ = try dependency(expression, bit: bit, expressions: expressions, operands: operands, context: &context)
                                    _ = try symbol(expression, bit: bit, expressions: expressions, operands: operands, context: &context)
                                }
                            }
                        }
                        frozenDepth += 1; try flow.append(.endGroup, context: &context)
                    }
                    for position in range.reversed() { try flow.append(.visit(children[position].rawValue), context: &context) }
                case .conditional(let condition, let yes, let no):
                    let root = try predicate(condition.rawValue, expressions: expressions, operands: operands, context: &context)
                    let conditionSymbol = try symbol(condition.rawValue, bit: 0, expressions: expressions, operands: operands, context: &context)
                    let gate = try guards.atom(conditionSymbol, context: &context)
                    if gate == 1 { try flow.append(.visit(yes.rawValue), context: &context) }
                    else if gate == 0 { if let no { try flow.append(.visit(no.rawValue), context: &context) } }
                    else {
                        let index = frames.count
                        try frames.append(.init(journalStart: journal.count, resultsStart: branchValues.count, condition: root, predicate: gate,
                            accumulated: nil, branches: .conditional(yes.rawValue, no?.rawValue, 0)), context: &context)
                        if case .body(let first) = try nextBranch(index, items: items, context: &context) {
                            try flow.append(.branchEnd(index), context: &context)
                            if let first { try flow.append(.visit(first), context: &context) }
                        }
                    }
                case .caseStatement(let selector, let range, let fallback):
                    var root = try predicate(selector.rawValue, expressions: expressions, operands: operands, context: &context)
                    for position in range {
                        var gate = 0
                        for match in items[position].matches {
                            let dependency = try predicate(matches[match].rawValue, expressions: expressions, operands: operands, context: &context)
                            root = try union(root, dependency, context: &context)
                            let condition = try caseGuard(selector: selector.rawValue, match: matches[match].rawValue, expressions: expressions, operands: operands, context: &context)
                            gate = try guards.or(gate, condition, context: &context)
                        }
                        caseGuards[position] = gate
                    }
                    let index = frames.count
                    try frames.append(.init(journalStart: journal.count, resultsStart: branchValues.count, condition: root, predicate: 0,
                        accumulated: nil, branches: .caseStatement(range, fallback?.rawValue, false)), context: &context)
                    if case .body(let first) = try nextBranch(index, items: items, context: &context) {
                        try flow.append(.branchEnd(index), context: &context)
                        if let first { try flow.append(.visit(first), context: &context) }
                    }
                }
            }
        }
    }
}
