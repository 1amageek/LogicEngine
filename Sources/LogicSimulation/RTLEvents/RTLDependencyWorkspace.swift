import LogicIR
import LogicKernelCore

internal struct RTLDependencyWorkspace: ~Copyable {
    enum Node { case source(Int), union(Int, Int) }
    struct Version {
        var environment: Int
        var environmentTag: UInt64 = 0
        var symbol = 0
        var guardRoot = 0
        var blocking = -1
        var blockingPossible = false
        var pending = -1
        var pendingTag: UInt64 = 0
        var pendingSymbol = 0
        var pendingGuard = 0
        var pendingPossible = false
        var pendingDefinite = false
        var assignedDefinite = false
        var finalSymbol = 0
        var finalData = -1
        var finalTag: UInt64 = 0
    }
    struct Journal { let bit: Int; let previous: Version }
    struct BranchValue { let bit: Int; let version: Version }
    enum Evaluation { case visit(Int, Int), finish(Int, Int) }
    enum Flow { case visit(Int), branchEnd(Int), endGroup }
    enum Branches {
        case conditional(Int, Int?, Int)
        case caseStatement(Range<Int>, Int?, Bool)
    }
    struct BranchFrame {
        let journalStart: Int
        let resultsStart: Int
        let condition: Int
        let predicate: Int
        var currentGuard = 0
        var coveredGuard = 0
        var remainingGuard = 1
        var accumulated: Range<Int>?
        var branches: Branches
    }
    let design: ElaboratedRTL
    let bitCount: Int
    let expressionBitCount: Int
    let statementStackCapacity: Int
    var offsets: [Int]
    var expressionOffsets: [Int]
    var reads: [Bool]
    var writes: [Bool]
    var blockingFF: [Bool]
    var versions: [Version]
    var cache: [Int]
    var cacheEpoch: [UInt64]
    var symbolCache: [Int]
    var symbolEpoch: [UInt64]
    var caseGuards: [Int]
    var guards = RTLGuardWorkspace()
    var epoch: UInt64 = 1
    var serial: UInt64 = 0
    var frozenDepth = 0
    var process = 0
    var sourceFlags: [Bool]
    var stamps: [UInt64]
    var locations: [Int]
    var finalRoots: [Int]
    var writers: [Int]
    var retained: [Bool]
    var frames = RTLAdmissionBuffer<BranchFrame>()
    var flow = RTLAdmissionBuffer<Flow>()
    var arena = RTLAdmissionBuffer<Node>()
    var evaluation = RTLAdmissionBuffer<Evaluation>()
    var traversal = RTLAdmissionBuffer<Int>()
    var journal = RTLAdmissionBuffer<Journal>()
    var branchValues = RTLAdmissionBuffer<BranchValue>()
    var assignment = RTLAdmissionBuffer<Int>()
    var assignmentSymbols = RTLAdmissionBuffer<Int>()

    init(design: borrowing ElaboratedRTL, context: inout LogicKernelContext) throws(LogicKernelError) {
        var bits = 0; var expressionBits = 0; var stackCapacity = 0; var caseCount = 0
        try design.withProgram { signals, statements, children, items, _, _, _ throws(LogicKernelError) in
            for index in signals.indices {
                try context.charge(.workUnits)
                let next = bits.addingReportingOverflow(signals[index].type.width.value)
                guard !next.overflow else { throw .invalidInput("RTL dependency bit count overflows") }; bits = next.partialValue
            }
            caseCount = items.count
            let doubled = statements.count.multipliedReportingOverflow(by: 2)
            let total = doubled.partialValue.addingReportingOverflow(children.count)
            guard !doubled.overflow, !total.overflow else { throw .invalidInput("RTL statement stack capacity overflows") }
            stackCapacity = total.partialValue
        }
        try design.withExpressions { expressions, _, _ throws(LogicKernelError) in
            for index in expressions.indices {
                try context.charge(.workUnits)
                let next = expressionBits.addingReportingOverflow(expressions[index].type.width.value)
                guard !next.overflow else { throw .invalidInput("RTL expression bit count overflows") }; expressionBits = next.partialValue
            }
        }
        let matrix = bits.multipliedReportingOverflow(by: design.processCount)
        guard !matrix.overflow, design.signalCount < Int.max, design.expressionCount < Int.max else { throw .invalidInput("RTL dependency dimensions overflow") }
        var bytes = UInt64(MemoryLayout<RTLDependencyWorkspace>.stride)
        for (count, stride) in [(design.signalCount + 1, MemoryLayout<Int>.stride),
            (design.expressionCount + 1, MemoryLayout<Int>.stride), (matrix.partialValue, 3 * MemoryLayout<Bool>.stride),
            (bits, MemoryLayout<Version>.stride + 3 * MemoryLayout<Int>.stride + MemoryLayout<UInt64>.stride + 2 * MemoryLayout<Bool>.stride),
            (expressionBits, 2 * (MemoryLayout<Int>.stride + MemoryLayout<UInt64>.stride)),
            (caseCount, MemoryLayout<Int>.stride)] {
            let payload = UInt64(count).multipliedReportingOverflow(by: UInt64(stride))
            let total = bytes.addingReportingOverflow(payload.partialValue)
            guard !payload.overflow, !total.overflow else { throw .invalidInput("RTL dependency storage overflows") }; bytes = total.partialValue
        }
        // Fixed payload follows invocation admission; growing scratch buffers below
        // separately account old/new overlap and release their live receipts.
        _ = try context.reserveStorage(byteCount: bytes)
        self.design = copy design; bitCount = bits; expressionBitCount = expressionBits; statementStackCapacity = stackCapacity
        offsets = .init(repeating: 0, count: design.signalCount + 1)
        expressionOffsets = .init(repeating: 0, count: design.expressionCount + 1)
        reads = .init(repeating: false, count: matrix.partialValue)
        writes = .init(repeating: false, count: matrix.partialValue)
        blockingFF = .init(repeating: false, count: matrix.partialValue)
        versions = .init(repeating: Version(environment: -1), count: bits)
        cache = .init(repeating: -1, count: expressionBits); cacheEpoch = .init(repeating: 0, count: expressionBits)
        symbolCache = .init(repeating: 0, count: expressionBits); symbolEpoch = .init(repeating: 0, count: expressionBits)
        caseGuards = .init(repeating: 0, count: caseCount)
        sourceFlags = .init(repeating: false, count: bits); stamps = .init(repeating: 0, count: bits)
        locations = .init(repeating: -1, count: bits); finalRoots = .init(repeating: -1, count: bits)
        writers = .init(repeating: -1, count: bits); retained = .init(repeating: false, count: bits)
    }
    mutating func nextEpoch() throws(LogicKernelError) {
        guard frozenDepth == 0 else { return }
        let next = epoch.addingReportingOverflow(1)
        guard !next.overflow else { throw .invalidInput("RTL dependency epoch exhausted") }; epoch = next.partialValue
    }
    mutating func nextSerial() throws(LogicKernelError) -> UInt64 {
        let next = serial.addingReportingOverflow(1)
        guard !next.overflow else { throw .invalidInput("RTL dependency version exhausted") }; serial = next.partialValue; return serial
    }
    mutating func union(_ a: Int, _ b: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> Int {
        if a == -1 { return b }; if b == -1 || a == b { return a }
        guard arena.count < Int.max - bitCount else { throw .invalidInput("RTL dependency identity space exhausted") }
        let index = arena.count; try arena.append(.union(a, b), context: &context); return index
    }
    mutating func remember(bit: Int, version: Version, context: inout LogicKernelContext) throws(LogicKernelError) {
        if frames.count > 0 { try journal.append(.init(bit: bit, previous: versions[bit]), context: &context) }
        versions[bit] = version
    }
    mutating func sources(_ root: Int, context: inout LogicKernelContext) throws(LogicKernelError) {
        for bit in sourceFlags.indices { try context.charge(.workUnits); sourceFlags[bit] = false }
        traversal.truncate(0)
        if root >= 0 { try traversal.append(root, context: &context) }
        while let index = traversal.popLast() {
            try context.charge(.workUnits)
            switch arena[index] {
            case .source(let bit): sourceFlags[bit] = true
            case .union(let a, let b): try traversal.append(a, context: &context); try traversal.append(b, context: &context)
            }
        }
    }
    mutating func markReads(_ root: Int, context: inout LogicKernelContext) throws(LogicKernelError) {
        try sources(root, context: &context)
        for bit in sourceFlags.indices {
            try context.charge(.workUnits)
            if sourceFlags[bit] { reads[process * bitCount + bit] = true }
        }
    }
    mutating func release(context: inout LogicKernelContext) throws(LogicKernelError) {
        try guards.release(context: &context)
        try frames.release(context: &context); try flow.release(context: &context); try arena.release(context: &context)
        try evaluation.release(context: &context); try traversal.release(context: &context); try journal.release(context: &context)
        try branchValues.release(context: &context); try assignment.release(context: &context); try assignmentSymbols.release(context: &context)
    }
}
