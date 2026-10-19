import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
extension ProceduralLoweringWorkspace {
    mutating func sampleAssignmentGroup(_ root: Int, statements: borrowing Span<RTLResolvedStatement>,
                                       children: borrowing Span<RTLStatementIndex>,
                                       expressions: borrowing Span<RTLResolvedExpression>,
                                       inputs: borrowing Span<RTLExpressionIndex>,
                                       context: inout LogicKernelContext) throws(LogicKernelError) {
        guard !assignmentGroupActive, pending.count == 0 else {
            throw .invalidModel("Assignment snapshot overlaps another traversal")
        }
        let generation = assignmentGeneration.addingReportingOverflow(1)
        guard !generation.overflow else {
            throw .resourceLimit(resource: .workUnits, limit: context.limits[.workUnits], requested: nil)
        }
        assignmentGeneration = generation.partialValue
        try pending.append(root, receipt: &receipt, bytes: &bytes, context: &context)
        // Word nodes are immutable expressions of this pre-write environment.
        // Sampling changes no bit record; nested groups share the same snapshot.
        while let index = pending.popLast() {
            try context.charge(.workUnits)
            switch statements[index].operation {
            case .empty: break
            case .assignment(_, _, let expression, _):
                _ = try sampleAssignmentExpression(expression.rawValue, expressions: expressions,
                    inputs: inputs, context: &context)
            case .assignmentGroup(let range):
                for offset in range.reversed() {
                    try pending.append(children[offset].rawValue, receipt: &receipt, bytes: &bytes, context: &context)
                }
            case .conditional(let test, let yes, let no):
                let condition = try sampleAssignmentExpression(test.rawValue, expressions: expressions,
                    inputs: inputs, context: &context)
                if let value = booleanConstant(condition) {
                    if value {
                        try pending.append(yes.rawValue, receipt: &receipt, bytes: &bytes, context: &context)
                    } else if let no {
                        try pending.append(no.rawValue, receipt: &receipt, bytes: &bytes, context: &context)
                    }
                } else {
                    if let no { try pending.append(no.rawValue, receipt: &receipt, bytes: &bytes, context: &context) }
                    try pending.append(yes.rawValue, receipt: &receipt, bytes: &bytes, context: &context)
                }
            case .block, .caseStatement:
                throw .invalidModel("Assignment groups contain an invalid program operation")
            }
        }
    }

    mutating func sampleAssignmentExpression(_ index: Int, expressions: borrowing Span<RTLResolvedExpression>,
                                            inputs: borrowing Span<RTLExpressionIndex>,
                                            context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        if assignmentSamples[index].stamp == assignmentGeneration { return assignmentSamples[index].value }
        let value = try evaluate(index, expressions: expressions, inputs: inputs, context: &context)
        assignmentSamples[index] = CachedExpression(stamp: assignmentGeneration, value: value)
        return value
    }

    mutating func programExpression(_ index: Int, expressions: borrowing Span<RTLResolvedExpression>,
                                   inputs: borrowing Span<RTLExpressionIndex>,
                                   context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        guard assignmentGroupActive else {
            return try evaluate(index, expressions: expressions, inputs: inputs, context: &context)
        }
        guard assignmentSamples[index].stamp == assignmentGeneration else {
            throw .invalidModel("Assignment expression was not sampled before its writes")
        }
        return assignmentSamples[index].value
    }
}
