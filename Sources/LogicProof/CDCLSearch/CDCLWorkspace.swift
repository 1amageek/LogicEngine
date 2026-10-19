import LogicKernelCore

internal struct CDCLWorkspace: ~Copyable {
    private struct Clause { let range: Range<Int>; let first: Int; let second: Int }
    private struct Watch { let clause: Int; var position: Int; var next: Int }
    private let variableCount: Int
    private var values: [Int8]
    private var levels: [Int]
    private var reasons: [Int]
    private var seen: [Bool]
    private var heads: [Int]
    private var trail: [LogicSATLiteral]
    private var boundaries: [Int]
    private var learned: [LogicSATLiteral]
    private var clauses = ProofBuffer<Clause>()
    private var literals = ProofBuffer<LogicSATLiteral>()
    private var watches = ProofBuffer<Watch>()
    private var scratch: LogicStorageReservation?
    private var qhead = 0
    private var statistics = LogicSATStatistics()
    private var learnedLiteralCount = 0

    init(variableCount: Int, context: inout LogicKernelContext) throws(LogicKernelError) {
        let count = variableCount.addingReportingOverflow(1)
        let headsCount = count.partialValue.multipliedReportingOverflow(by: 2)
        guard !count.overflow, !headsCount.overflow else { throw .invalidInput("Search variable index capacity overflows") }
        // Fixed arrays include the reserved trail, decision boundaries and analysis clause.
        let stride = MemoryLayout<Int8>.stride + MemoryLayout<Int>.stride * 5 + MemoryLayout<Bool>.stride + MemoryLayout<LogicSATLiteral>.stride * 2
        let bytes = UInt64(count.partialValue).multipliedReportingOverflow(by: UInt64(stride))
        let total = bytes.partialValue.addingReportingOverflow(UInt64(MemoryLayout<Self>.stride))
        guard !bytes.overflow, !total.overflow else { throw .invalidInput("Search workspace payload overflows") }
        let receipt = try context.reserveStorage(byteCount: total.partialValue)
        self.variableCount = variableCount
        values = .init(repeating: -1, count: count.partialValue)
        levels = .init(repeating: 0, count: count.partialValue)
        reasons = .init(repeating: -1, count: count.partialValue)
        seen = .init(repeating: false, count: count.partialValue)
        heads = .init(repeating: -1, count: headsCount.partialValue)
        trail = []; trail.reserveCapacity(variableCount)
        boundaries = []; boundaries.reserveCapacity(variableCount)
        learned = []; learned.reserveCapacity(count.partialValue)
        scratch = consume receipt
    }
    private func slot(_ literal: LogicSATLiteral) -> Int { literal.variable.rawValue * 2 + (literal.isPositive ? 0 : 1) }
    private func truth(_ literal: LogicSATLiteral) -> Int8 {
        let value = values[literal.variable.rawValue]
        return value < 0 ? -1 : (literal.isPositive ? value : 1 - value)
    }
    private mutating func enqueue(_ literal: LogicSATLiteral, reason: Int) -> Bool {
        let variable = literal.variable.rawValue
        if values[variable] >= 0 { return truth(literal) == 1 }
        values[variable] = literal.isPositive ? 1 : 0
        levels[variable] = boundaries.count; reasons[variable] = reason
        trail.append(literal)
        return true
    }
    private mutating func addClause(_ input: borrowing Span<LogicSATLiteral>, learned isLearned: Bool, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        let identifier = clauses.count
        let start = literals.count
        if isLearned {
            let count = identifier.addingReportingOverflow(1)
            guard !count.overflow else { throw .invalidInput("Search clause count overflows") }
            try context.require(.cnfClauses, amount: UInt64(count.partialValue))
            try context.charge(.cnfClauses)
        }
        for index in input.indices { try literals.append(input[index], context: &context) }
        let range = start..<literals.count
        let first = input.isEmpty ? -1 : watches.count
        if !input.isEmpty {
            let key = slot(input[0])
            try watches.append(.init(clause: identifier, position: start, next: heads[key]), context: &context)
            heads[key] = first
        }
        let second = input.count < 2 ? -1 : watches.count
        if input.count >= 2 {
            let key = slot(input[1])
            try watches.append(.init(clause: identifier, position: start + 1, next: heads[key]), context: &context)
            heads[key] = second
        }
        try clauses.append(.init(range: range, first: first, second: second), context: &context)
        return identifier
    }
    private mutating func propagate(context: inout LogicKernelContext) throws(LogicKernelError) -> Int? {
        while qhead < trail.count {
            try context.charge(.searchSteps)
            statistics.propagations += 1
            let key = slot(trail[qhead].negated); qhead += 1
            var previous = -1
            var current = heads[key]
            while current >= 0 {
                try context.charge(.workUnits)
                let record = watches[current]
                let clause = clauses[record.clause]
                let other = clause.first == current ? clause.second : clause.first
                let next = record.next
                if other < 0 { return record.clause }
                let otherPosition = watches[other].position
                let otherLiteral = literals[otherPosition]
                if truth(otherLiteral) == 1 { previous = current; current = next; continue }
                var replacement = -1
                for position in clause.range {
                    try context.charge(.workUnits)
                    if position != record.position && position != otherPosition && truth(literals[position]) != 0 {
                        replacement = position; break
                    }
                }
                if replacement >= 0 {
                    if previous < 0 { heads[key] = next } else { watches[previous].next = next }
                    let replacementKey = slot(literals[replacement])
                    watches[current].position = replacement
                    watches[current].next = heads[replacementKey]
                    heads[replacementKey] = current
                    statistics.watchRelocations += 1
                } else {
                    if !enqueue(otherLiteral, reason: record.clause) { return record.clause }
                    previous = current
                }
                current = next
            }
        }
        return nil
    }
    private mutating func analyze(_ conflict: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        learned.removeAll(keepingCapacity: true)
        // The reserved slot is replaced by the negation of the first UIP below.
        learned.append(literals[clauses[conflict].range.lowerBound])
        for variable in seen.indices { try context.charge(.workUnits); seen[variable] = false }
        var pending = 0
        var clause = conflict
        var pivotVariable = 0
        var position = trail.count
        while true {
            for index in clauses[clause].range {
                try context.charge(.workUnits)
                let literal = literals[index]; let variable = literal.variable.rawValue
                if variable == pivotVariable || seen[variable] || levels[variable] == 0 { continue }
                seen[variable] = true
                if levels[variable] == boundaries.count { pending += 1 } else { learned.append(literal) }
            }
            var pivot: LogicSATLiteral?
            while position > 0 {
                try context.charge(.workUnits); position -= 1
                if seen[trail[position].variable.rawValue] { pivot = trail[position]; break }
            }
            guard let pivot, pending > 0 else { throw .invalidModel("Conflict graph has no current-level implication point") }
            pivotVariable = pivot.variable.rawValue
            seen[pivotVariable] = false; pending -= 1
            if pending == 0 { learned[0] = pivot.negated; break }
            clause = reasons[pivotVariable]
            guard clause >= 0 else { throw .invalidModel("Conflict analysis reached an unresolved decision") }
        }
        var target = 0
        var highest = 1
        for index in 1..<learned.count {
            try context.charge(.workUnits)
            let level = levels[learned[index].variable.rawValue]
            if level > target { target = level; highest = index }
        }
        // Watch the asserting literal and the greatest other level after backjump.
        if learned.count > 1 { learned.swapAt(1, highest) }
        return target
    }
    private mutating func backtrack(to level: Int, context: inout LogicKernelContext) throws(LogicKernelError) {
        let end = boundaries[level]
        for position in end..<trail.count {
            try context.charge(.workUnits)
            let variable = trail[position].variable.rawValue
            values[variable] = -1; levels[variable] = 0; reasons[variable] = -1
        }
        trail.removeLast(trail.count - end)
        boundaries.removeLast(boundaries.count - level)
        qhead = trail.count
    }
    private func certificate(_ formula: borrowing LogicCNFFormula, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicRUPCertificate {
        let count = clauses.count - formula.clauseCount
        let capacity = count.addingReportingOverflow(1)
        guard !capacity.overflow else { throw .invalidInput("Search proof step count overflows") }
        try context.charge(.outputBytes, amount: try proofPayload(clauses: capacity.partialValue, literals: learnedLiteralCount))
        var builder = try LogicRUPBuilder(formula: formula, clauseCapacity: capacity.partialValue, literalCapacity: learnedLiteralCount, context: &context)
        for index in formula.clauseCount..<clauses.count {
            try literals.withSlice(clauses[index].range) { values throws(LogicKernelError) in
                try builder.appendClause(values, context: &context)
            }
        }
        try builder.appendClause([], context: &context)
        return try builder.finish(context: &context)
    }
    mutating func solve(_ formula: borrowing LogicCNFFormula, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicSATOutcome {
        var rootConflict = false
        try formula.withClauses { ranges, values throws(LogicKernelError) in
            for index in ranges.indices {
                let range = ranges[index]
                let clause = try addClause(values.extracting(range), learned: false, context: &context)
                if range.isEmpty { rootConflict = true }
                if range.count == 1 && !enqueue(values[range.lowerBound], reason: clause) { rootConflict = true }
            }
        }
        while true {
            try context.checkpoint()
            let conflict = rootConflict ? 0 : try propagate(context: &context)
            if let conflict {
                try context.charge(.searchSteps); statistics.conflicts += 1
                if boundaries.isEmpty { return .unsatisfiable(try certificate(formula, context: &context), statistics) }
                let target = try analyze(conflict, context: &context)
                statistics.backjumps += 1
                if target < boundaries.count - 1 { statistics.nonChronologicalBackjumps += 1 }
                try backtrack(to: target, context: &context)
                let sum = learnedLiteralCount.addingReportingOverflow(learned.count)
                guard !sum.overflow else { throw .invalidInput("Search proof literal count overflows") }
                learnedLiteralCount = sum.partialValue
                let stepCount = Int(statistics.learnedClauses).addingReportingOverflow(2)
                guard !stepCount.overflow else { throw .invalidInput("Search proof step count overflows") }
                try context.require(.proofBytes, amount: try proofPayload(clauses: stepCount.partialValue, literals: learnedLiteralCount))
                // A local COW owner permits borrowing analysis output while other workspace tables mutate.
                let addition = learned
                let clause = try addClause(addition.span, learned: true, context: &context)
                statistics.learnedClauses += 1
                guard enqueue(learned[0], reason: clause) else { throw .invalidModel("Learned clause is not asserting after backjump") }
            } else {
                var decision = 0
                for variable in 1..<(variableCount + 1) {
                    try context.charge(.workUnits)
                    if values[variable] < 0 { decision = variable; break }
                }
                if decision == 0 {
                    let bytes = UInt64(values.count).addingReportingOverflow(LogicSATAssignment.storageByteCount)
                    guard !bytes.overflow else { throw .invalidInput("SAT output payload overflows") }
                    _ = try context.reserveStorage(byteCount: bytes.partialValue)
                    try context.charge(.outputBytes, amount: UInt64(variableCount))
                    // The immutable output retains this COW allocation until workspace release.
                    let assignment = LogicSATAssignment(formula: formula, values: values)
                    try assignment.validate(formula, context: &context)
                    return .satisfiable(assignment, statistics)
                }
                try context.charge(.searchSteps); statistics.decisions += 1
                boundaries.append(trail.count)
                _ = enqueue(.init(variable: .init(validated: decision), positive: false), reason: -1)
            }
        }
    }
    private func proofPayload(clauses: Int, literals: Int) throws(LogicKernelError) -> UInt64 {
        let count = UInt64(clauses).addingReportingOverflow(UInt64(literals))
        let payload = count.partialValue.multipliedReportingOverflow(by: 8)
        let total = payload.partialValue.addingReportingOverflow(16)
        guard !count.overflow, !payload.overflow, !total.overflow else { throw .invalidInput("Search proof payload overflows") }
        return total.partialValue
    }
    mutating func release(context: inout LogicKernelContext) throws(LogicKernelError) {
        values = []; levels = []; reasons = []; seen = []; heads = []; trail = []; boundaries = []; learned = []
        try clauses.release(context: &context)
        try literals.release(context: &context)
        try watches.release(context: &context)
        let receipt = scratch.take()
        if let receipt { try context.releaseStorage(receipt) }
    }
}
