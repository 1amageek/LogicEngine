import LogicIR
import LogicKernelCore

extension RTLDependencyWorkspace {
    enum NextBranch { case body(Int?), finished }
    mutating func nextBranch(_ index: Int, items: borrowing Span<RTLResolvedCaseItem>, context: inout LogicKernelContext) throws(LogicKernelError) -> NextBranch {
        var frame = frames[index]
        let result: NextBranch
        switch frame.branches {
        case .conditional(let yes, let no, let phase):
            frame.currentGuard = phase == 0 ? frame.predicate : try guards.not(frame.predicate, context: &context)
            result = phase == 0 ? .body(yes) : phase == 1 ? .body(no) : .finished
            frame.branches = .conditional(yes, no, phase + 1)
        case .caseStatement(let range, let fallback, let complete):
            if !range.isEmpty {
                let gate = caseGuards[range.lowerBound]
                frame.currentGuard = try guards.and(frame.remainingGuard, gate, context: &context)
                frame.remainingGuard = try guards.and(frame.remainingGuard, guards.not(gate, context: &context), context: &context)
                result = .body(items[range.lowerBound].body.rawValue)
                frame.branches = .caseStatement((range.lowerBound + 1)..<range.upperBound, fallback, complete)
            } else if !complete {
                frame.currentGuard = frame.remainingGuard
                result = .body(fallback); frame.branches = .caseStatement(range, fallback, true)
            } else { result = .finished }
        }
        frames[index] = frame
        if frame.currentGuard == 0, case .body = result { return .body(nil) }
        return result
    }
    mutating func capture(_ frame: BranchFrame, context: inout LogicKernelContext) throws(LogicKernelError) -> Range<Int> {
        let start = branchValues.count
        let generation = try nextSerial()
        for index in frame.journalStart..<journal.count {
            try context.charge(.workUnits)
            let bit = journal[index].bit
            if stamps[bit] != generation {
                stamps[bit] = generation
                var value = versions[bit]
                value.guardRoot = try guards.and(value.guardRoot, frame.currentGuard, context: &context)
                value.pendingGuard = try guards.and(value.pendingGuard, frame.currentGuard, context: &context)
                try branchValues.append(.init(bit: bit, version: value), context: &context)
            }
        }
        while journal.count > frame.journalStart {
            try context.charge(.workUnits)
            guard let entry = journal.popLast() else { throw .invalidModel("RTL dependency journal underflow") }
            versions[entry.bit] = entry.previous
        }
        return start..<branchValues.count
    }
    mutating func merge(_ a: Version, _ b: Version, condition: Int, valueCondition: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Version {
        var result = a
        if a.environmentTag != b.environmentTag {
            result.environment = try union(a.environment, b.environment, context: &context)
            if a.symbol != b.symbol { result.environment = try union(result.environment, condition, context: &context) }
            result.environmentTag = try nextSerial()
        }
        result.blockingPossible = a.blockingPossible || b.blockingPossible
        if a.environmentTag != b.environmentTag, result.blockingPossible {
            result.blocking = try union(union(a.blocking, b.blocking, context: &context), condition, context: &context)
        }
        result.pendingGuard = try guards.or(a.pendingGuard, b.pendingGuard, context: &context)
        result.pendingPossible = result.pendingGuard != 0; result.pendingDefinite = result.pendingGuard == 1
        result.pendingSymbol = try mergedSymbol(condition: valueCondition, a: a.pendingSymbol, b: b.pendingSymbol, context: &context)
        if a.pendingTag != b.pendingTag {
            result.pending = try union(union(a.pending, b.pending, context: &context), condition, context: &context)
            result.pendingTag = try nextSerial()
        }
        result.guardRoot = try guards.or(a.guardRoot, b.guardRoot, context: &context)
        result.assignedDefinite = result.guardRoot == 1
        if a.symbol != b.symbol {
            result.symbol = try mergedSymbol(condition: valueCondition, a: a.symbol, b: b.symbol, context: &context)
        }
        result.finalSymbol = try mergedSymbol(condition: valueCondition, a: a.finalSymbol, b: b.finalSymbol, context: &context)
        if a.finalTag != b.finalTag {
            result.finalData = try union(a.finalData, b.finalData, context: &context)
            if a.finalSymbol != b.finalSymbol { result.finalData = try union(result.finalData, condition, context: &context) }
            result.finalTag = try nextSerial()
        }
        return result
    }
    mutating func mergeResults(_ a: Range<Int>, _ b: Range<Int>, condition: Int, covered: Int, current: Int, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Range<Int> {
        let generation = try nextSerial()
        for index in a {
            try context.charge(.workUnits)
            let bit = branchValues[index].bit; stamps[bit] = generation; locations[bit] = index
        }
        let start = branchValues.count
        for index in b {
            try context.charge(.workUnits)
            let second = branchValues[index]
            var first = stamps[second.bit] == generation ? branchValues[locations[second.bit]].version : versions[second.bit]
            if stamps[second.bit] != generation {
                first.guardRoot = try guards.and(first.guardRoot, covered, context: &context)
                first.pendingGuard = try guards.and(first.pendingGuard, covered, context: &context)
            }
            let value = try merge(first, second.version, condition: condition, valueCondition: current, context: &context)
            try branchValues.append(.init(bit: second.bit, version: value), context: &context)
            stamps[second.bit] = 0
        }
        for index in a {
            try context.charge(.workUnits)
            let first = branchValues[index]
            if stamps[first.bit] == generation {
                var baseline = versions[first.bit]
                baseline.guardRoot = try guards.and(baseline.guardRoot, current, context: &context)
                baseline.pendingGuard = try guards.and(baseline.pendingGuard, current, context: &context)
                let value = try merge(first.version, baseline, condition: condition, valueCondition: current, context: &context)
                try branchValues.append(.init(bit: first.bit, version: value), context: &context)
            }
        }
        return start..<branchValues.count
    }
    mutating func branchEnd(_ index: Int, items: borrowing Span<RTLResolvedCaseItem>, context: inout LogicKernelContext)
        throws(LogicKernelError) {
        var frame = frames[index]
        let current = try capture(frame, context: &context)
        try nextEpoch()
        if frame.currentGuard != 0 {
            if let previous = frames[index].accumulated {
                frame.accumulated = try mergeResults(previous, current, condition: frame.condition, covered: frame.coveredGuard, current: frame.currentGuard, context: &context)
            } else { frame.accumulated = current }
            frame.coveredGuard = try guards.or(frame.coveredGuard, frame.currentGuard, context: &context)
        }
        frames[index] = frame
        switch try nextBranch(index, items: items, context: &context) {
        case .body(let body):
            try flow.append(.branchEnd(index), context: &context)
            if let body { try flow.append(.visit(body), context: &context) }
        case .finished:
            guard let result = frames[index].accumulated else { throw .invalidModel("RTL branch result is missing") }
            let start = frames[index].resultsStart
            frames.truncate(index)
            for position in result {
                try context.charge(.workUnits)
                let value = branchValues[position]
                try remember(bit: value.bit, version: value.version, context: &context)
            }
            branchValues.truncate(start)
            try nextEpoch()
        }
    }
}
