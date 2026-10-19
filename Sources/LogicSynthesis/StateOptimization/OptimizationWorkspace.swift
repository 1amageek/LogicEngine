import LogicIR
import LogicKernelCore

internal struct OptimizationWorkspace: ~Copyable {
    private var drafts: [OptimizationDraft] = []
    private var table: [OptimizationKey: Int] = [:]
    private var sourceMap: [Int]
    private var destination: [Int]
    private var live: [Bool]
    private var stack: [Int] = []
    private var operandScratch: [BitNodeIndex] = []
    private var portScratch: [BitNodeIndex] = []
    private var receipt: LogicStorageReservation?
    private var constantFolds = 0
    private var commonSubexpressions = 0

    init(source: borrowing BitLogicDesign, context: inout LogicKernelContext) throws(LogicKernelError) {
        let n = source.nodeCount
        let bytes = try Self.bytes(n, MemoryLayout<OptimizationDraft>.stride + MemoryLayout<(OptimizationKey, Int)>.stride + 3 * MemoryLayout<Int>.stride + MemoryLayout<Bool>.stride)
        let ports = try Self.bytes(source.portBitCount, MemoryLayout<BitNodeIndex>.stride)
        let total = try Self.sum(try Self.sum(bytes, ports), 3 * UInt64(MemoryLayout<BitNodeIndex>.stride))
        let reservation = try context.reserveStorage(byteCount: total)
        sourceMap = .init(repeating: -1, count: n); destination = .init(repeating: -1, count: n)
        live = .init(repeating: false, count: n)
        drafts.reserveCapacity(n); table.reserveCapacity(n); stack.reserveCapacity(n)
        operandScratch.reserveCapacity(3); portScratch.reserveCapacity(source.portBitCount)
        receipt = consume reservation
    }
    private static func bytes(_ count: Int, _ stride: Int) throws(LogicKernelError) -> UInt64 {
        let value = UInt64(count).multipliedReportingOverflow(by: UInt64(stride))
        guard !value.overflow else { throw .invalidInput("Optimization storage overflows") }
        return value.partialValue
    }
    private static func sum(_ a: UInt64, _ b: UInt64) throws(LogicKernelError) -> UInt64 {
        let value = a.addingReportingOverflow(b)
        guard !value.overflow else { throw .invalidInput("Optimization storage overflows") }
        return value.partialValue
    }
    mutating func release(context: inout LogicKernelContext) throws(LogicKernelError) {
        drafts = []; table = [:]; sourceMap = []; destination = []; live = []; stack = []
        operandScratch = []; portScratch = []
        let old = receipt.take()
        if let old { try context.releaseStorage(old) }
    }
    private mutating func intern(_ key: OptimizationKey, node: borrowing BitLogicNode) -> Int {
        if let existing = table[key] { commonSubexpressions += 1; return existing }
        let result = drafts.count
        drafts.append(.init(key: key, id: node.id, origin: node.origin)); table[key] = result
        return result
    }
    private func constant(_ index: Int) -> Bool? {
        if case .constant(let value) = drafts[index].key { return value }
        return nil
    }
    private func complements(_ a: Int, _ b: Int) -> Bool {
        if case .invert(let inner) = drafts[a].key, inner == b { return true }
        if case .invert(let inner) = drafts[b].key, inner == a { return true }
        return false
    }
    private mutating func invert(_ a: Int, node: borrowing BitLogicNode) -> Int {
        if let c = constant(a) { return intern(.constant(!c), node: node) }
        if case .invert(let inner) = drafts[a].key { return inner }
        return intern(.invert(a), node: node)
    }
    private mutating func canonicalize(_ node: borrowing BitLogicNode, index: Int, operands: borrowing Span<BitNodeIndex>) -> Int {
        let a = node.operands.isEmpty ? -1 : sourceMap[operands[node.operands.lowerBound].rawValue]
        let b = node.operands.count < 2 ? -1 : sourceMap[operands[node.operands.lowerBound + 1].rawValue]
        let c = node.operands.count < 3 ? -1 : sourceMap[operands[node.operands.lowerBound + 2].rawValue]
        switch node.operation {
        case .input: return intern(.input(index), node: node)
        case .state(let s): return intern(.state(s.rawValue), node: node)
        case .constant(let v): return intern(.constant(v), node: node)
        case .buffer: return a
        case .invert: return invert(a, node: node)
        case .and:
            if constant(a) == false || constant(b) == false || complements(a,b) { return intern(.constant(false), node: node) }
            if constant(a) == true { return b }; if constant(b) == true || a == b { return a }
            return intern(.and(min(a,b), max(a,b)), node: node)
        case .or:
            if constant(a) == true || constant(b) == true || complements(a,b) { return intern(.constant(true), node: node) }
            if constant(a) == false { return b }; if constant(b) == false || a == b { return a }
            return intern(.or(min(a,b), max(a,b)), node: node)
        case .xor:
            if a == b { return intern(.constant(false), node: node) }
            if complements(a,b) { return intern(.constant(true), node: node) }
            if let v = constant(a) { return v ? invert(b, node: node) : b }
            if let v = constant(b) { return v ? invert(a, node: node) : a }
            return intern(.xor(min(a,b), max(a,b)), node: node)
        case .select:
            if let v = constant(a) { return v ? b : c }
            if b == c { return b }
            if let bv = constant(b), let cv = constant(c), bv != cv { return bv ? a : invert(a, node: node) }
            if case .invert(let inner) = drafts[a].key { return intern(.select(inner,c,b), node: node) }
            return intern(.select(a,b,c), node: node)
        }
    }
    private mutating func mark(_ source: BitNodeIndex) { markCanonical(sourceMap[source.rawValue]) }
    private mutating func markCanonical(_ index: Int) {
        if !live[index] { live[index] = true; stack.append(index) }
    }
    private func mapped(_ source: BitNodeIndex) -> BitNodeIndex { .init(destination[sourceMap[source.rawValue]]) }
    private func reset(_ old: BitReset?) -> BitReset? {
        guard let old else { return nil }
        return .init(signal: mapped(old.signal), activeHigh: old.activeHigh, value: old.value, kind: old.kind)
    }
    mutating func run(source: borrowing BitLogicDesign, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicOptimizationCandidate {
        let sourceOwner = copy source
        return try source.withTables { (nodes, operands, ports, bits, states, order) throws(LogicKernelError) in
            for position in order.indices {
                try context.charge(.workUnits)
                let index = order[position].rawValue
                let canonical = canonicalize(nodes[index], index: index, operands: operands)
                sourceMap[index] = canonical
                if case .constant = drafts[canonical].key {
                    if case .constant = nodes[index].operation {} else { constantFolds += 1 }
                }
            }
            for index in nodes.indices {
                try context.charge(.workUnits)
                switch nodes[index].operation { case .input, .state: mark(.init(index)); default: break }
            }
            for p in ports.indices where ports[p].direction == .output {
                for index in ports[p].bits { try context.charge(.workUnits); mark(bits[index]) }
            }
            for index in states.indices {
                try context.charge(.workUnits); let state = states[index]; mark(state.next)
                switch state.control {
                case .flipFlop(let clock, _, let enable, let r):
                    mark(clock); if let enable { mark(enable) }; if let r { mark(r.signal) }
                case .latch(let gate, _, let r): mark(gate); if let r { mark(r.signal) }
                }
            }
            while let index = stack.popLast() {
                let key = drafts[index].key
                for offset in 0..<key.operandCount { try context.charge(.workUnits); markCanonical(key.operand(offset)) }
            }
            var count = 0; var edges = 0
            for index in drafts.indices {
                try context.charge(.workUnits)
                if live[index] {
                    count += 1
                    let next = edges.addingReportingOverflow(drafts[index].key.operandCount)
                    guard !next.overflow else { throw .invalidInput("Optimization edges overflow") }; edges = next.partialValue
                }
            }
            var builder = try BitLogicBuilder(capacity: .init(nodes: count, operands: edges, ports: ports.count,
                portBits: bits.count, states: states.count), context: &context)
            for index in drafts.indices where live[index] {
                try context.charge(.workUnits)
                let draft = drafts[index]; operandScratch.removeAll(keepingCapacity: true)
                for offset in 0..<draft.key.operandCount { operandScratch.append(.init(destination[draft.key.operand(offset)])) }
                let added = try builder.addNode(id: draft.id, operation: draft.key.operation, inputs: operandScratch, origin: draft.origin, context: &context)
                destination[index] = added.rawValue
            }
            for index in ports.indices {
                portScratch.removeAll(keepingCapacity: true)
                for bit in ports[index].bits { try context.charge(.workUnits); portScratch.append(mapped(bits[bit])) }
                try builder.addPort(id: ports[index].id, direction: ports[index].direction, bits: portScratch, context: &context)
            }
            for index in states.indices {
                try context.charge(.workUnits); let old = states[index]; let control: BitStateControl
                switch old.control {
                case .flipFlop(let clock, let edge, let enable, let r):
                    control = .flipFlop(clock: mapped(clock), edge: edge, enable: enable.map { mapped($0) }, reset: reset(r))
                case .latch(let gate, let activeHigh, let r): control = .latch(gate: mapped(gate), activeHigh: activeHigh, reset: reset(r))
                }
                _ = try builder.addState(.init(id: old.id, next: mapped(old.next), control: control, initialValue: old.initialValue, origin: old.origin), context: &context)
            }
            let design = try builder.finish(context: &context)
            let originBytes = try Self.sum(Self.bytes(nodes.count, MemoryLayout<LogicOptimizationOrigin>.stride), UInt64(LogicOptimizationCandidate.storageByteCount))
            _ = try context.reserveStorage(byteCount: originBytes)
            var origins: [LogicOptimizationOrigin] = []; origins.reserveCapacity(nodes.count)
            for index in nodes.indices {
                try context.charge(.workUnits)
                let final = destination[sourceMap[index]]
                origins.append(.init(source: .init(index), destination: final < 0 ? nil : .init(final)))
            }
            return LogicOptimizationCandidate(source: sourceOwner, design: design, origins: origins,
                statistics: .init(sourceNodes: nodes.count, resultNodes: count, constantFolds: constantFolds, commonSubexpressions: commonSubexpressions))
        }
    }
}
