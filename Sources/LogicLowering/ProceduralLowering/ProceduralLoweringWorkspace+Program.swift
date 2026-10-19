import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension ProceduralLoweringWorkspace {
    mutating func execute(_ root: Int, statements: borrowing Span<RTLResolvedStatement>,
                          children: borrowing Span<RTLStatementIndex>, items: borrowing Span<RTLResolvedCaseItem>,
                          matches: borrowing Span<RTLExpressionIndex>, expressions: borrowing Span<RTLResolvedExpression>,
                          expressionOperands: borrowing Span<RTLExpressionIndex>, context: inout LogicKernelContext)
        throws(LogicKernelError) {
        try commands.append(.target(.statement(root)), receipt: &receipt, bytes: &bytes, context: &context)
        while let command = commands.popLast() {
            try context.charge(.workUnits)
            switch command {
            case .finishAssignmentGroup:
                guard assignmentGroupActive else { throw .invalidModel("Assignment snapshot lifetime is invalid") }
                assignmentGroupActive = false
            case .target(.empty): break
            case .target(.statement(let index)):
                try executeStatement(index, statements: statements, children: children, items: items,
                    matches: matches, expressions: expressions, expressionOperands: expressionOperands,
                    context: &context)
            case .target(.caseTest(let selector, let item, let end, let fallback, let exhaustive)):
                if item == end {
                    if let fallback { try commands.append(.target(.statement(fallback)), receipt: &receipt, bytes: &bytes, context: &context) }
                    continue
                }
                if exhaustive && item == end - 1 {
                    try commands.append(.target(.statement(items[item].body.rawValue)), receipt: &receipt, bytes: &bytes, context: &context)
                    continue
                }
                var condition = 0
                for offset in items[item].matches {
                    let value = try evaluate(matches[offset].rawValue, expressions: expressions, inputs: expressionOperands, context: &context)
                    let equal = try compute(.equal, type: scalar, a: selector, b: value,
                                            origin: items[item].origin, context: &context)
                    condition = try compute(.or, type: scalar, a: condition, b: equal,
                                             origin: items[item].origin, context: &context)
                }
                try branch(condition, yes: .statement(items[item].body.rawValue),
                    no: .caseTest(selector: selector, item: item + 1, end: end, fallback: fallback, exhaustive: exhaustive),
                    context: &context)
            case .afterTrue(let condition, let otherwise, let mark):
                let start = deltas.count
                try captureAndUndo(since: mark, context: &context)
                try commands.append(.afterFalse(condition: condition, journalStart: mark, trueStart: start, trueEnd: deltas.count),
                                    receipt: &receipt, bytes: &bytes, context: &context)
                try commands.append(.target(otherwise), receipt: &receipt, bytes: &bytes, context: &context)
            case .afterFalse(let condition, let mark, let trueStart, let trueEnd):
                let falseStart = deltas.count
                try captureAndUndo(since: mark, context: &context)
                let falseEnd = deltas.count
                for index in trueStart..<trueEnd { bits[deltas[index].bit].trueDelta = index }
                for index in falseStart..<falseEnd { bits[deltas[index].bit].falseDelta = index }
                for index in trueStart..<trueEnd {
                    try context.charge(.workUnits)
                    let location = deltas[index].bit; let other = bits[location].falseDelta
                    let no = other < 0 ? bits[location].record : deltas[other].record
                    let merged = try merge(condition, yes: deltas[index].record, no: no, context: &context)
                    try update(location, record: merged, context: &context)
                }
                for index in falseStart..<falseEnd {
                    try context.charge(.workUnits)
                    let location = deltas[index].bit
                    if bits[location].trueDelta < 0 {
                        let merged = try merge(condition, yes: bits[location].record, no: deltas[index].record, context: &context)
                        try update(location, record: merged, context: &context)
                    }
                }
                for index in trueStart..<falseEnd {
                    bits[deltas[index].bit].trueDelta = -1; bits[deltas[index].bit].falseDelta = -1
                }
                deltas.truncate(trueStart)
            }
        }
    }

    mutating func branch(_ condition: Int, yes: Target, no: Target, context: inout LogicKernelContext)
        throws(LogicKernelError) {
        if let constant = booleanConstant(condition) {
            try commands.append(.target(constant ? yes : no), receipt: &receipt, bytes: &bytes, context: &context)
        } else {
            try commands.append(.afterTrue(condition: condition, otherwise: no, journalStart: journal.count),
                                receipt: &receipt, bytes: &bytes, context: &context)
            try commands.append(.target(yes), receipt: &receipt, bytes: &bytes, context: &context)
        }
    }

    mutating func update(_ bit: Int, record: Record, context: inout LogicKernelContext) throws(LogicKernelError) {
        try journal.append(Change(bit: bit, record: bits[bit].record), receipt: &receipt, bytes: &bytes, context: &context)
        bits[bit].record = record
    }

    mutating func captureAndUndo(since mark: Int, context: inout LogicKernelContext) throws(LogicKernelError) {
        let generation = journalGeneration.addingReportingOverflow(1)
        guard !generation.overflow else {
            throw .resourceLimit(resource: .workUnits, limit: context.limits[.workUnits], requested: nil)
        }
        journalGeneration = generation.partialValue
        while journal.count > mark {
            try context.charge(.workUnits)
            let change = journal.popLast()!
            if bits[change.bit].stamp != journalGeneration {
                try deltas.append(Change(bit: change.bit, record: bits[change.bit].record),
                                  receipt: &receipt, bytes: &bytes, context: &context)
                bits[change.bit].stamp = journalGeneration
            }
            bits[change.bit].record = change.record
        }
    }

    mutating func merge(_ condition: Int, yes: Record, no: Record, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Record {
        Record(current: try select(condition, yes.current, no.current, context: &context),
            blockingData: try select(condition, yes.blockingData, no.blockingData, context: &context),
            blockingEnable: try select(condition, yes.blockingEnable, no.blockingEnable, context: &context),
            nbaData: try select(condition, yes.nbaData, no.nbaData, context: &context),
            nbaEnable: try select(condition, yes.nbaEnable, no.nbaEnable, context: &context),
            complete: yes.complete && no.complete)
    }

    func exhaustiveCase(_ range: Range<Int>, items: borrowing Span<RTLResolvedCaseItem>,
                        matches: borrowing Span<RTLExpressionIndex>, expressions: borrowing Span<RTLResolvedExpression>,
                        selectorType: WordLogicType, context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        let width = selectorType.width.value
        guard width < Int.bitWidth - 1, !range.isEmpty else { return false }
        let first = items[range.lowerBound].matches.lowerBound
        let end = items[range.upperBound - 1].matches.upperBound
        let required = 1 << width
        guard end - first >= required else { return false }
        var unique = 0
        for index in first..<end {
            try context.charge(.workUnits)
            guard case .constant(let value) = expressions[matches[index].rawValue].operation, value.isTwoState else { return false }
            var duplicate = false
            for earlier in first..<index {
                try context.charge(.workUnits, amount: UInt64(value.width.wordCount))
                if case .constant(let old) = expressions[matches[earlier].rawValue].operation, old == value {
                    duplicate = true; break
                }
            }
            if !duplicate { unique += 1 }
        }
        return unique == required
    }
}
