import CircuiteFoundation
import LogicIR
import LogicKernelCore

@available(macOS 26.0, *)
internal struct ProceduralLoweringWorkspace: ~Copyable {
    struct DraftNode {
        let type: WordLogicType
        var operation: WordLogicOperation?
        let operands: Range<Int>
        var alias: Int?
        let origin: LogicKernelSourceRange?
    }
    struct Signal {
        let offset: Int
        let type: WordLogicType
        let initial: LogicFourStateVector?
        let origin: LogicKernelSourceRange?
        var input: Int = -1
    }
    struct Record {
        var current: Int
        var blockingData: Int = 0
        var blockingEnable: Int = 0
        var nbaData: Int = 0
        var nbaEnable: Int = 0
        var complete: Bool = false
    }
    struct BitSlot {
        var writer = -1
        var proxy = -1
        var state = -1
        var reset: WordReset?
        var blockingFFWriter = false
        var record = Record(current: -1)
        var stamp: UInt64 = 0
        var trueDelta = -1
        var falseDelta = -1
    }
    struct Change { let bit: Int; let record: Record }
    struct CachedExpression { var stamp: UInt64 = 0; var value = -1 }
    enum Target {
        case statement(Int)
        case caseTest(selector: Int, item: Int, end: Int, fallback: Int?, exhaustive: Bool)
        case empty
    }
    enum Command {
        case target(Target)
        case finishAssignmentGroup
        case afterTrue(condition: Int, otherwise: Target, journalStart: Int)
        case afterFalse(condition: Int, journalStart: Int, trueStart: Int, trueEnd: Int)
    }

    var receipt: LogicStorageReservation
    var bytes: UInt64 = 0
    var nodes = ProceduralBuffer<DraftNode>()
    var operands = ProceduralBuffer<Int>()
    var signals = ProceduralBuffer<Signal>()
    var bits = ProceduralBuffer<BitSlot>()
    var cached = ProceduralBuffer<CachedExpression>()
    var assignmentSamples = ProceduralBuffer<CachedExpression>()
    var expressionStack = ProceduralBuffer<(Int, Bool)>()
    var commands = ProceduralBuffer<Command>()
    var journal = ProceduralBuffer<Change>()
    var deltas = ProceduralBuffer<Change>()
    var states = ProceduralBuffer<WordLogicState?>()
    var ports = ProceduralBuffer<WordLogicPort>()
    var pending = ProceduralBuffer<Int>()
    var mapping = ProceduralBuffer<Int>()
    var publicationInputs = ProceduralBuffer<WordNodeIndex>()
    var controls = ProceduralBuffer<(Int, Int, Int, Int, Int)>()
    var stateBits = ProceduralBuffer<Int>()
    var demands = ProceduralBuffer<(Int, Range<Int>)>()
    var seenDemands = ProceduralBuffer<(Int, Range<Int>)>()
    var expressionGeneration: UInt64 = 0
    var journalGeneration: UInt64 = 0
    var assignmentGeneration: UInt64 = 0
    var assignmentGroupActive = false
    var resetOverride: (expression: Int, value: Int)?
    let scalar: WordLogicType

    init(receipt: consuming LogicStorageReservation, scalar: WordLogicType) {
        self.receipt = receipt; self.scalar = scalar
    }

    consuming func release(context: inout LogicKernelContext) throws(LogicKernelError) {
        try context.releaseStorage(receipt)
    }

    func entity(_ ordinal: Int) throws(LogicKernelError) -> DesignEntityID {
        do { return try DesignEntityID(rawValue: UInt64(ordinal) + 1) }
        catch { throw .invalidModel("Generated word entity identity is invalid") }
    }

    func failure(_ message: String, origin: LogicKernelSourceRange?) -> LogicKernelError {
        if let origin { return .sourceFailure(code: .trusted("logic.word-lowering.unsupported"), source: origin, message: message) }
        return .unsupported(message)
    }

    mutating func emit(type: WordLogicType, operation: WordLogicOperation?, a: Int = -1,
                       b: Int = -1, c: Int = -1, origin: LogicKernelSourceRange? = nil,
                       context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        try context.charge(.expansion)
        try context.observeBitWidth(UInt64(type.width.value))
        let start = operands.count
        if a >= 0 { try operands.append(a, receipt: &receipt, bytes: &bytes, context: &context) }
        if b >= 0 { try operands.append(b, receipt: &receipt, bytes: &bytes, context: &context) }
        if c >= 0 { try operands.append(c, receipt: &receipt, bytes: &bytes, context: &context) }
        let index = nodes.count
        try nodes.append(DraftNode(type: type, operation: operation, operands: start..<operands.count,
            origin: origin), receipt: &receipt, bytes: &bytes, context: &context)
        return index
    }

    func booleanConstant(_ index: Int) -> Bool? {
        guard case .constant(let value) = nodes[index].operation, value.width.value == 1 else { return nil }
        // Only admitted binary scalar constants are constructed in this workspace.
        return value.withPlanes { words, _ in words[0] == 1 }
    }

    mutating func select(_ condition: Int, _ whenTrue: Int, _ whenFalse: Int,
                         origin: LogicKernelSourceRange? = nil, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Int {
        if whenTrue == whenFalse { return whenTrue }
        if let value = booleanConstant(condition) { return value ? whenTrue : whenFalse }
        if whenTrue == 1 && whenFalse == 0 { return condition }
        if whenTrue == 0 && whenFalse == 1 {
            return try control(1, a: condition, origin: origin, context: &context)
        }
        if nodes[whenTrue].type == scalar {
            return try control(0, a: condition, b: whenTrue, c: whenFalse, origin: origin, context: &context)
        }
        return try emit(type: nodes[whenTrue].type, operation: .compute(.select), a: condition,
                        b: whenTrue, c: whenFalse, origin: origin, context: &context)
    }

    mutating func control(_ tag: Int, a: Int, b: Int = -1, c: Int = -1,
                          origin: LogicKernelSourceRange? = nil, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Int {
        // Intern control expressions so one logical latch gate has one dense identity.
        // The bounded linear table owns only procedural control, not general circuit CSE.
        for index in controls.indices {
            try context.charge(.workUnits)
            let entry = controls[index]
            if entry.0 == tag && entry.1 == a && entry.2 == b && entry.3 == c { return entry.4 }
        }
        let opcode: WordLogicOpcode = tag == 0 ? .select : tag == 1 ? .logicalNot : tag == 2 ? .or : .and
        let result = try emit(type: scalar, operation: .compute(opcode), a: a, b: b, c: c, origin: origin, context: &context)
        try controls.append((tag, a, b, c, result), receipt: &receipt, bytes: &bytes, context: &context)
        return result
    }

    mutating func bit(_ value: Int, at offset: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        if nodes[value].type == scalar { return value }
        if case .constant(let vector) = nodes[value].operation {
            try context.charge(.workUnits)
            return try vector.bit(at: offset) == .one ? 1 : 0
        }
        return try emit(type: scalar, operation: .compute(.slice(offset: offset)), a: value,
                        origin: nodes[value].origin, context: &context)
    }

    mutating func readSignal(_ index: Int, current: Bool, context: inout LogicKernelContext)
        throws(LogicKernelError) -> Int {
        let signal = signals[index]
        if signal.input >= 0 { return signal.input }
        let width = signal.type.width.value
        if width == 1 {
            let value = current ? bits[signal.offset].record.current : bits[signal.offset].proxy
            if signal.type == scalar { return value }
            return try emit(type: signal.type, operation: .compute(.bitcast), a: value,
                            origin: signal.origin, context: &context)
        }
        let start = operands.count
        for bit in (0..<width).reversed() {
            try context.charge(.workUnits)
            let value = current ? bits[signal.offset + bit].record.current : bits[signal.offset + bit].proxy
            try operands.append(value, receipt: &receipt, bytes: &bytes, context: &context)
        }
        let unsigned = WordLogicType(width: signal.type.width)
        let value = nodes.count
        try context.charge(.expansion)
        try nodes.append(DraftNode(type: unsigned, operation: .compute(.concatenate), operands: start..<operands.count,
            origin: signal.origin), receipt: &receipt, bytes: &bytes, context: &context)
        if !signal.type.isSigned { return value }
        return try emit(type: signal.type, operation: .compute(.bitcast), a: value, origin: signal.origin, context: &context)
    }

    mutating func lower(_ design: borrowing ElaboratedRTL, context: inout LogicKernelContext)
        throws(LogicKernelError) -> WordLogicDesign {
        try design.withExpressions { (expressions: borrowing Span<RTLResolvedExpression>,
            expressionOperands: borrowing Span<RTLExpressionIndex>, _: borrowing Span<RTLExpressionIndex>) throws(LogicKernelError) in
            try design.withProgram { (sourceSignals: borrowing Span<RTLResolvedSignal>,
                statements: borrowing Span<RTLResolvedStatement>, children: borrowing Span<RTLStatementIndex>,
                items: borrowing Span<RTLResolvedCaseItem>, matches: borrowing Span<RTLExpressionIndex>,
                sourcePorts: borrowing Span<RTLResolvedPort>, processes: borrowing Span<RTLResolvedProcess>) throws(LogicKernelError) in
                try prepare(sourceSignals, expressions: expressions, statements: statements, children: children,
                            items: items, processes: processes, context: &context)
                for index in processes.indices {
                    try lowerProcess(index, processes: processes, statements: statements, children: children,
                                     items: items, matches: matches, expressions: expressions,
                                     expressionOperands: expressionOperands, context: &context)
                }
                for index in sourcePorts.indices {
                    let source = sourcePorts[index]
                    let value = try readSignal(source.signal.rawValue, current: false, context: &context)
                    try ports.append(WordLogicPort(id: source.id, direction: source.direction,
                        value: WordNodeIndex(value)), receipt: &receipt, bytes: &bytes, context: &context)
                }
                return try publish(context: &context)
            }
        }
    }
}
