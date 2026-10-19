import LogicIR
import LogicKernelCore

// Canonical value terms and reduced ordered decision diagrams qualify common
// write-enable functions without interpreting data dependencies as gate meaning.
internal struct RTLGuardWorkspace: ~Copyable {
    struct Symbol { let expression: Int; let bit: Int; let inputs: Range<Int> }
    struct Decision { let variable: Int; let low: Int; let high: Int }
    struct Memo { let condition: Int; let yes: Int; let no: Int; let result: Int }
    enum Task { case visit(Int, Int, Int), finish(Int, Int, Int, Int, Int, Int, Int, Int, Int, Int) }
    var symbols = RTLAdmissionBuffer<Symbol>()
    var inputs = RTLAdmissionBuffer<Int>()
    var temporary = RTLAdmissionBuffer<Int>()
    var decisions = RTLAdmissionBuffer<Decision>()
    var memo = RTLAdmissionBuffer<Memo>()
    var tasks = RTLAdmissionBuffer<Task>()
    mutating func initialize(context: inout LogicKernelContext) throws(LogicKernelError) {
        try decisions.append(.init(variable: Int.max, low: 0, high: 0), context: &context)
        try decisions.append(.init(variable: Int.max, low: 1, high: 1), context: &context)
    }
    mutating func convertedToTwoState(_ source: Int, base: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        if source < 4 { return source == Int(LogicBit.one.rawValue) ? 1 : 0 }
        if source >= base, symbols[source - base].expression == -3 { return source }
        // Negative expression identities distinguish conversion (-3), branch (-2) and case (-1) terms.
        for index in symbols.indices {
            try context.charge(.workUnits)
            let candidate = symbols[index]
            if candidate.expression == -3, inputs[candidate.inputs.lowerBound] == source { return base + index }
        }
        let result = base.addingReportingOverflow(symbols.count)
        guard !result.overflow else { throw .invalidInput("RTL conversion symbol count overflows") }
        let start = inputs.count
        try inputs.append(source, context: &context)
        try symbols.append(.init(expression: -3, bit: 0, inputs: start..<inputs.count), context: &context)
        return result.partialValue
    }
    mutating func intern(expression: Int, bit: Int, nodes: borrowing Span<RTLResolvedExpression>, operands: borrowing Span<RTLExpressionIndex>,
                         base: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        let source = nodes[expression]
        for index in symbols.indices {
            try context.charge(.workUnits)
            let candidate = symbols[index]
            if candidate.expression < 0 { continue }
            let previous = nodes[candidate.expression]
            guard candidate.bit == bit, source.type == previous.type, source.operands.count == previous.operands.count,
                  candidate.inputs.count == temporary.count else { continue }
            let same: Bool
            switch (source.operation, previous.operation) {
            case (.compute(let a), .compute(let b)): same = a == b
            case (.caseEqual, .caseEqual), (.dynamicSelect, .dynamicSelect): same = true
            default: same = false
            }
            if !same { continue }
            var equal = true
            for position in 0..<source.operands.count {
                try context.charge(.workUnits)
                if nodes[operands[source.operands.lowerBound + position].rawValue].type != nodes[operands[previous.operands.lowerBound + position].rawValue].type { equal = false; break }
            }
            if !equal { continue }
            for position in temporary.indices {
                try context.charge(.workUnits)
                if inputs[candidate.inputs.lowerBound + position] != temporary[position] { equal = false; break }
            }
            if equal { return base + index }
        }
        let start = inputs.count
        for index in temporary.indices { try inputs.append(temporary[index], context: &context) }
        let result = base.addingReportingOverflow(symbols.count)
        guard !result.overflow else { throw .invalidInput("RTL gate symbol count overflows") }
        try symbols.append(.init(expression: expression, bit: bit, inputs: start..<inputs.count), context: &context)
        return result.partialValue
    }
    mutating func node(_ variable: Int, _ low: Int, _ high: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        if low == high { return low }
        for index in decisions.indices {
            try context.charge(.workUnits)
            let candidate = decisions[index]
            if candidate.variable == variable && candidate.low == low && candidate.high == high { return index }
        }
        let result = decisions.count; try decisions.append(.init(variable: variable, low: low, high: high), context: &context); return result
    }
    mutating func atom(_ symbol: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        if symbol < 4 { return symbol == Int(LogicBit.one.rawValue) ? 1 : 0 }
        return try node(symbol, 0, 1, context: &context)
    }
    mutating func lookup(_ c: Int, _ t: Int, _ e: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> Int? {
        if c == 0 { return e }; if c == 1 { return t }; if t == e { return t }
        for index in memo.indices {
            try context.charge(.workUnits)
            let record = memo[index]
            if record.condition == c && record.yes == t && record.no == e { return record.result }
        }; return nil
    }
    func child(_ value: Int, variable: Int, high: Bool) -> Int {
        let record = decisions[value]
        return record.variable == variable ? (high ? record.high : record.low) : value
    }
    mutating func select(_ c: Int, _ t: Int, _ e: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        tasks.truncate(0); try tasks.append(.visit(c, t, e), context: &context)
        while let task = tasks.popLast() {
            try context.charge(.workUnits)
            switch task {
            case .visit(let c, let t, let e):
                if try lookup(c, t, e, context: &context) != nil { continue }
                let variable = min(decisions[c].variable, min(decisions[t].variable, decisions[e].variable))
                let cl = child(c, variable: variable, high: false); let ch = child(c, variable: variable, high: true)
                let tl = child(t, variable: variable, high: false); let th = child(t, variable: variable, high: true)
                let el = child(e, variable: variable, high: false); let eh = child(e, variable: variable, high: true)
                try tasks.append(.finish(c, t, e, variable, cl, tl, el, ch, th, eh), context: &context)
                try tasks.append(.visit(ch, th, eh), context: &context); try tasks.append(.visit(cl, tl, el), context: &context)
            case .finish(let c, let t, let e, let variable, let cl, let tl, let el, let ch, let th, let eh):
                guard let low = try lookup(cl, tl, el, context: &context), let high = try lookup(ch, th, eh, context: &context) else { throw .invalidModel("RTL gate decision operand missing") }
                let result = try node(variable, low, high, context: &context)
                try memo.append(.init(condition: c, yes: t, no: e, result: result), context: &context)
            }
        }
        guard let result = try lookup(c, t, e, context: &context) else { throw .invalidModel("RTL gate decision result missing") }; return result
    }
    mutating func and(_ a: Int, _ b: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> Int { try select(a, b, 0, context: &context) }
    mutating func or(_ a: Int, _ b: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> Int { try select(a, 1, b, context: &context) }
    mutating func not(_ a: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> Int { try select(a, 0, 1, context: &context) }
    mutating func release(context: inout LogicKernelContext) throws(LogicKernelError) {
        try symbols.release(context: &context); try inputs.release(context: &context); try temporary.release(context: &context)
        try decisions.release(context: &context); try memo.release(context: &context); try tasks.release(context: &context)
    }
}
