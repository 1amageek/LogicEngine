import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension ProceduralLoweringWorkspace {
    mutating func executeStatement(_ index: Int, statements: borrowing Span<RTLResolvedStatement>,
                                  children: borrowing Span<RTLStatementIndex>,
                                  items: borrowing Span<RTLResolvedCaseItem>, matches: borrowing Span<RTLExpressionIndex>,
                                  expressions: borrowing Span<RTLResolvedExpression>,
                                  expressionOperands: borrowing Span<RTLExpressionIndex>,
                                  context: inout LogicKernelContext) throws(LogicKernelError) {
        let statement = statements[index]
        switch statement.operation {
        case .empty: break
        case .assignment(let target, let selection, let expression, let timing):
            let value = try programExpression(expression.rawValue, expressions: expressions, inputs: expressionOperands, context: &context)
            for offset in 0..<selection.count {
                try context.charge(.workUnits)
                let location = signals[target.rawValue].offset + selection.lowerBound + offset
                let valueBit = try bit(value, at: offset, context: &context)
                var record = bits[location].record
                switch timing {
                case .blocking:
                    record.current = valueBit; record.blockingData = valueBit; record.blockingEnable = 1
                case .nonBlocking:
                    record.nbaData = valueBit; record.nbaEnable = 1
                }
                record.complete = true
                try update(location, record: record, context: &context)
            }
        case .assignmentGroup(let range):
            if !assignmentGroupActive {
                try sampleAssignmentGroup(index, statements: statements, children: children,
                    expressions: expressions, inputs: expressionOperands, context: &context)
                assignmentGroupActive = true
                try commands.append(.finishAssignmentGroup, receipt: &receipt, bytes: &bytes, context: &context)
            }
            for offset in range.reversed() {
                try commands.append(.target(.statement(children[offset].rawValue)), receipt: &receipt, bytes: &bytes, context: &context)
            }
        case .block(let range):
            for offset in range.reversed() {
                try commands.append(.target(.statement(children[offset].rawValue)), receipt: &receipt, bytes: &bytes, context: &context)
            }
        case .conditional(let test, let yes, let no):
            let condition = try programExpression(test.rawValue, expressions: expressions, inputs: expressionOperands, context: &context)
            try branch(condition, yes: .statement(yes.rawValue), no: no.map { .statement($0.rawValue) } ?? .empty,
                       context: &context)
        case .caseStatement(let selector, let range, let fallback):
            let value = try evaluate(selector.rawValue, expressions: expressions, inputs: expressionOperands, context: &context)
            let exhaustive: Bool
            if fallback == nil {
                exhaustive = try exhaustiveCase(range, items: items, matches: matches,
                    expressions: expressions, selectorType: expressions[selector.rawValue].type, context: &context)
            } else { exhaustive = false }
            try commands.append(.target(.caseTest(selector: value, item: range.lowerBound, end: range.upperBound,
                fallback: fallback?.rawValue, exhaustive: exhaustive)), receipt: &receipt, bytes: &bytes, context: &context)
        }
    }
}
