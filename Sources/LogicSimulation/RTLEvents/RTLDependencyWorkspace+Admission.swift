import LogicIR
import LogicKernelCore

extension RTLDependencyWorkspace {
    mutating func run(context: inout LogicKernelContext) throws(LogicKernelError) -> RTLSimulationPlan {
        try guards.initialize(context: &context)
        guard bitCount <= Int.max - 4 else { throw .invalidInput("RTL symbol base overflows") }
        return try design.withProgram { signals, statements, children, items, matches, _, processes throws(LogicKernelError) in
            for index in signals.indices { offsets[index + 1] = offsets[index] + signals[index].type.width.value }
            try design.withExpressions { expressions, operands, _ throws(LogicKernelError) in
                for index in expressions.indices { expressionOffsets[index + 1] = expressionOffsets[index] + expressions[index].type.width.value }
                for bit in 0..<bitCount { try arena.append(.source(bit), context: &context) }; serial = UInt64(bitCount)
                var latchGate: Int?
                for index in processes.indices {
                    process = index
                    for bit in versions.indices {
                        try context.charge(.workUnits)
                        versions[bit] = Version(environment: bit, environmentTag: UInt64(bit) + 1, symbol: bit + 4, finalSymbol: bit + 4)
                    }
                    try nextEpoch()
                    var isFF = false
                    if case .flipFlop(let clock, _, let reset) = processes[index].control {
                        isFF = true
                        _ = try predicate(clock.rawValue, expressions: expressions, operands: operands, context: &context)
                        if let reset { _ = try predicate(reset.signal.rawValue, expressions: expressions, operands: operands, context: &context) }
                    }
                    try execute(processes[index].body.rawValue, statements: statements, children: children, items: items,
                        matches: matches, expressions: expressions, operands: operands, signals: signals, isFF: isFF, context: &context)
                    for bit in 0..<bitCount where writes[index * bitCount + bit] {
                        try context.charge(.workUnits)
                        finalRoots[bit] = versions[bit].finalData
                        if case .combinational = processes[index].control, !versions[bit].assignedDefinite {
                            throw .unsupported("always_comb must assign every written bit on every path")
                        }
                        var explicitLatch = false
                        if case .latch = processes[index].control { explicitLatch = true }
                        retained[bit] = isFF || explicitLatch || !versions[bit].assignedDefinite
                        if retained[bit] && !isFF {
                            if let latchGate, latchGate != versions[bit].guardRoot { throw .unsupported("RTL latch profile requires one canonical write gate and polarity") }
                            latchGate = versions[bit].guardRoot
                        }
                    }
                    switch processes[index].control {
                    case .combinational, .latch:
                        for bit in 0..<bitCount where writes[index * bitCount + bit] { reads[index * bitCount + bit] = false }
                    default: break
                    }
                }
            }
            try validateDependencies(processes: processes, context: &context)
            var hasFF = false; var hasLatch = false
            var stateCount = 0
            for bit in 0..<bitCount where writers[bit] >= 0 {
                try context.charge(.workUnits)
                if case .flipFlop = processes[writers[bit]].control { hasFF = true }
                else if retained[bit] { hasLatch = true }
                if retained[bit] { stateCount += 1 }
            }
            guard !(hasFF && hasLatch) else { throw .unsupported("RTL event profile cannot mix FF and inferred latch state") }
            try context.require(.states, amount: UInt64(stateCount))
            _ = try context.reserveStorage(byteCount: RTLSimulationPlan.payloadByteCount)
            let result = RTLSimulationPlan(design: design, offsets: offsets, reads: reads, writes: writes,
                blockingFF: blockingFF, stateCount: stateCount, statementStackCapacity: statementStackCapacity)
            try release(context: &context)
            return result
        }
    }
    mutating func validateDependencies(processes: borrowing Span<RTLResolvedProcess>, context: inout LogicKernelContext) throws(LogicKernelError) {
        // Iterative path coloring uses source bits as graph vertices. Arena nodes
        // contain prior references only; implicit hold has no transparent root.
        _ = try context.reserveStorage(byteCount: UInt64(bitCount) * UInt64(MemoryLayout<UInt8>.stride))
        var colors = [UInt8](repeating: 0, count: bitCount)
        for start in 0..<bitCount where colors[start] == 0 {
            traversal.truncate(0); try traversal.append(start, context: &context)
            while let entry = traversal.popLast() {
                try context.charge(.workUnits)
                if entry < 0 { colors[-entry - 1] = 2; continue }
                if entry >= bitCount {
                    switch arena[entry - bitCount] {
                    case .source(let bit): try traversal.append(bit, context: &context)
                    case .union(let a, let b): try traversal.append(a + bitCount, context: &context); try traversal.append(b + bitCount, context: &context)
                    }; continue
                }
                if colors[entry] == 2 { continue }
                guard colors[entry] != 1 else { throw .unsupported("RTL contains a transparent bit dependency cycle") }
                colors[entry] = 1; try traversal.append(-entry - 1, context: &context)
                let writer = writers[entry]
                if writer < 0 { continue }
                if case .flipFlop = processes[writer].control { continue }
                if finalRoots[entry] >= 0 { try traversal.append(finalRoots[entry] + bitCount, context: &context) }
            }
        }
        for reader in processes.indices {
            guard case .flipFlop = processes[reader].control else { continue }
            for bit in colors.indices { colors[bit] = 0 }
            traversal.truncate(0)
            for bit in 0..<bitCount where reads[reader * bitCount + bit] { try traversal.append(bit, context: &context) }
            while let entry = traversal.popLast() {
                try context.charge(.workUnits)
                if entry >= bitCount {
                    switch arena[entry - bitCount] {
                    case .source(let bit): try traversal.append(bit, context: &context)
                    case .union(let a, let b): try traversal.append(a + bitCount, context: &context); try traversal.append(b + bitCount, context: &context)
                    }; continue
                }
                if colors[entry] != 0 { continue }; colors[entry] = 1
                let writer = writers[entry]; if writer < 0 { continue }
                if case .flipFlop = processes[writer].control {
                    if writer != reader && blockingFF[writer * bitCount + entry] { throw .unsupported("FF processes have an Active-region blocking bit race") }
                } else if finalRoots[entry] >= 0 { try traversal.append(finalRoots[entry] + bitCount, context: &context) }
            }
        }
    }
}
