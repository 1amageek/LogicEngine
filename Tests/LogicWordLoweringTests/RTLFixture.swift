import CircuiteFoundation
import LogicIR
import LogicKernelCore

struct RTLFixture: ~Copyable {
    struct Control: LogicRunControlling {
        let failure: LogicKernelError?
        init(_ failure: LogicKernelError? = nil) { self.failure = failure }
        func checkpoint() throws(LogicKernelError) { if let failure { throw failure } }
    }
    static func context(storage: UInt64 = 1_000_000_000, work: UInt64 = 1_000_000_000,
                        control: Control = Control()) throws -> LogicKernelContext {
        var limits = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(1_000_000_000)) })
        limits[.managedStorageBytes] = storage; limits[.workUnits] = work
        return LogicKernelContext(limits: try LogicKernelLimits(maximums: limits), control: control)
    }
    static func type(_ width: Int, signed: Bool = false) throws -> WordLogicType {
        WordLogicType(width: try LogicBitWidth(width), isSigned: signed)
    }
    static func vector(_ value: UInt64, width: Int, unknown: UInt64 = 0) throws -> LogicFourStateVector {
        let size = try LogicBitWidth(width)
        var values = [UInt64](repeating: 0, count: size.wordCount); values[0] = value
        var unknowns = [UInt64](repeating: 0, count: size.wordCount); unknowns[0] = unknown
        return try LogicFourStateVector(width: size, valueWords: values, unknownWords: unknowns)
    }
    static func make(context: inout LogicKernelContext) throws -> RTLFixture {
        let builder = try ElaboratedRTLBuilder(topModuleID: DesignEntityID(rawValue: 1),
            capacity: RTLResolvedCapacity(signals: 32, expressions: 256, operands: 512, statements: 256,
                children: 512, caseItems: 64, caseMatches: 128, ports: 40, processes: 32), context: &context)
        return RTLFixture(builder: builder)
    }
    var builder: ElaboratedRTLBuilder
    var ordinal: UInt64 = 10
    init(builder: consuming ElaboratedRTLBuilder) { self.builder = builder }
    mutating func id() throws -> DesignEntityID { ordinal += 1; return try DesignEntityID(rawValue: ordinal) }
    mutating func signal(_ width: Int = 1, input: Bool = false, signed: Bool = false,
                         initial: LogicFourStateVector? = nil, origin: LogicKernelSourceRange? = nil,
                         context: inout LogicKernelContext) throws -> (RTLSignalIndex, RTLExpressionIndex) {
        let type = try Self.type(width, signed: signed)
        let signalID = try id()
        let signal = try builder.addSignal(RTLResolvedSignal(id: signalID, type: type, isInput: input,
            initialValue: initial, origin: origin), context: &context)
        let expressionID = try id()
        let read = try builder.addExpression(id: expressionID, type: type, operation: .read(signal), origin: origin, context: &context)
        if input { try output(signal, direction: .input, context: &context) }
        return (signal, read)
    }
    mutating func output(_ signal: RTLSignalIndex, direction: BitLogicPort.Direction = .output,
                         context: inout LogicKernelContext) throws {
        let portID = try id()
        try builder.addPort(RTLResolvedPort(id: portID, name: "p\(ordinal)", direction: direction, signal: signal), context: &context)
    }
    mutating func constant(_ value: UInt64, width: Int = 1, signed: Bool = false, unknown: UInt64 = 0,
                           origin: LogicKernelSourceRange? = nil, context: inout LogicKernelContext) throws -> RTLExpressionIndex {
        let expressionID = try id()
        return try builder.addExpression(id: expressionID, type: Self.type(width, signed: signed),
            operation: .constant(Self.vector(value, width: width, unknown: unknown)), origin: origin, context: &context)
    }
    mutating func compute(_ opcode: WordLogicOpcode, width: Int, signed: Bool = false,
                          _ inputs: [RTLExpressionIndex], context: inout LogicKernelContext) throws -> RTLExpressionIndex {
        let expressionID = try id()
        return try builder.addExpression(id: expressionID, type: Self.type(width, signed: signed),
            operation: .compute(opcode), inputs: inputs, context: &context)
    }
    mutating func assign(_ target: RTLSignalIndex, _ value: RTLExpressionIndex, range: Range<Int> = 0..<1,
                         nba: Bool = false, context: inout LogicKernelContext) throws -> RTLStatementIndex {
        let statementID = try id()
        return try builder.addStatement(RTLResolvedStatement(id: statementID,
            operation: .assignment(target: target, selection: range, value: value, timing: nba ? .nonBlocking : .blocking)), context: &context)
    }
    mutating func block(_ children: [RTLStatementIndex], context: inout LogicKernelContext) throws -> RTLStatementIndex {
        let statementID = try id()
        return try builder.addBlock(id: statementID, body: children, context: &context)
    }
    mutating func atomic(_ children: [RTLStatementIndex], context: inout LogicKernelContext) throws -> RTLStatementIndex {
        let statementID = try id()
        return try builder.addAssignmentGroup(id: statementID, body: children, context: &context)
    }
    mutating func branch(_ condition: RTLExpressionIndex, _ yes: RTLStatementIndex, _ no: RTLStatementIndex? = nil,
                         context: inout LogicKernelContext) throws -> RTLStatementIndex {
        let statementID = try id()
        return try builder.addStatement(RTLResolvedStatement(id: statementID,
            operation: .conditional(condition: condition, ifTrue: yes, ifFalse: no)), context: &context)
    }
    mutating func process(_ body: RTLStatementIndex, control: RTLResolvedProcess.Control = .combinational,
                          context: inout LogicKernelContext) throws {
        let processID = try id()
        try builder.addProcess(RTLResolvedProcess(id: processID, control: control, body: body), context: &context)
    }
    consuming func finish(context: inout LogicKernelContext) throws -> ElaboratedRTL { try builder.finish(context: &context) }
}
