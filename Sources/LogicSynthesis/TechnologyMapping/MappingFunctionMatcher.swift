import CircuiteFoundation
import LogicIR
import LogicKernelCore

internal struct MappingFunctionMatcher: ~Copyable {
    let library: LogicTechnologyLibrary
    let maximumInputs: Int
    private var values: [UInt64]
    private var reachability: [Bool]
    private var bindings: [Int]
    private var support: [Int]
    init(library: borrowing LogicTechnologyLibrary, maximumInputs: Int, functionCapacity: Int, pinCapacity: Int) {
        self.library = copy library; self.maximumInputs = maximumInputs
        values = .init(repeating: 0, count: functionCapacity)
        reachability = .init(repeating: false, count: functionCapacity)
        bindings = []; bindings.reserveCapacity(pinCapacity); support = []; support.reserveCapacity(pinCapacity)
    }
    mutating func supportOf(_ function: borrowing LogicBooleanFunction, context: inout LogicKernelContext)
        throws(LogicKernelError) -> [Int] {
        for i in 0..<function.nodeCount { try context.charge(.workUnits); reachability[i] = false }
        reachability[function.output.rawValue] = true; support.removeAll(keepingCapacity: true)
        try function.withOperations { operations throws(LogicKernelError) in
            for i in operations.indices.reversed() where reachability[i] {
                try context.charge(.workUnits)
                switch operations[i] {
                case .input(let slot): if !support.contains(slot) { support.append(slot) }
                case .invert(let a): reachability[a.rawValue] = true
                case .and(let a, let b), .or(let a, let b), .xor(let a, let b): reachability[a.rawValue] = true; reachability[b.rawValue] = true
                case .constant: break
                }
            }
        }
        support.sort(); return support
    }
    mutating func truth(_ function: borrowing LogicBooleanFunction, bindings: borrowing [Int], count: Int,
                        context: inout LogicKernelContext) throws(LogicKernelError) -> UInt64 {
        let mask = MappingArithmetic.mask(count)
        return try function.withOperations { operations throws(LogicKernelError) in
            for i in operations.indices {
                try context.charge(.workUnits)
                switch operations[i] {
                case .constant(let b): values[i] = b ? mask : 0
                case .input(let slot):
                    let code = bindings[slot]
                    if code < 2 { values[i] = code == 0 ? 0 : mask }
                    else {
                        let v = MappingArithmetic.variable((code - 2) / 2, count: count)
                        values[i] = code % 2 == 0 ? v : v ^ mask
                    }
                case .invert(let a): values[i] = values[a.rawValue] ^ mask
                case .and(let a, let b): values[i] = values[a.rawValue] & values[b.rawValue]
                case .or(let a, let b): values[i] = values[a.rawValue] | values[b.rawValue]
                case .xor(let a, let b): values[i] = values[a.rawValue] ^ values[b.rawValue]
                }
            }
            return values[function.output.rawValue]
        }
    }
    private func preferable(_ candidate: MappingMatch, to old: MappingMatch?) throws(LogicKernelError) -> Bool {
        guard let old else { return true }
        if candidate.area != old.area { return candidate.area < old.area }
        if candidate.depth != old.depth { return candidate.depth < old.depth }
        let a = try library.cell(at: candidate.cell).id.rawValue
        let b = try library.cell(at: old.cell).id.rawValue
        if a != b { return a < b }
        if candidate.bindings != old.bindings { return candidate.bindings.lexicographicallyPrecedes(old.bindings) }
        if candidate.output != old.output { return candidate.output.rawValue < old.output.rawValue }
        return !candidate.invertedOutput && old.invertedOutput
    }
    private func retained(_ match: borrowing MappingMatch, context: inout LogicKernelContext)
        throws(LogicKernelError) -> MappingMatch {
        let bytes = try MappingArithmetic.product(match.bindings.count, MemoryLayout<Int>.stride)
        let receipt = try context.reserveStorage(byteCount: UInt64(bytes))
        var copy: [Int] = []; copy.reserveCapacity(match.bindings.count)
        do throws(LogicKernelError) {
            for i in match.bindings.indices { try context.charge(.workUnits); copy.append(match.bindings[i]) }
        } catch { try context.releaseStorage(receipt); throw error }
        // Persistent pattern capacity is already admitted by the owning workspace.
        try context.releaseStorage(receipt)
        return .init(cell: match.cell, output: match.output, bindings: copy,
            invertedOutput: match.invertedOutput, area: match.area, depth: match.depth)
    }
    mutating func combinational(truth target: UInt64, count: Int, inverter: MappingMatch?,
                                context: inout LogicKernelContext) throws(LogicKernelError) -> MappingMatch? {
        var required = 0
        for variable in 0..<count {
            for row in 0..<(1 << count) where row & (1 << variable) == 0 {
                try context.charge(.workUnits)
                if ((target >> row) ^ (target >> (row | (1 << variable)))) & 1 != 0 { required |= 1 << variable; break }
            }
        }
        var best: MappingMatch?
        for ci in 0..<library.cellCount {
            let cell = try library.cell(at: .init(ci)); try context.charge(.workUnits)
            guard cell.state == nil else { continue }
            for output in 0..<cell.pinCount {
                try context.charge(.workUnits)
                guard let function = try cell.pin(at: .init(output)).function else { continue }
                let slots = try supportOf(function, context: &context)
                guard slots.count <= maximumInputs, slots.count >= required.nonzeroBitCount else { continue }
                bindings.removeAll(keepingCapacity: true)
                for _ in 0..<cell.pinCount { bindings.append(0) }
                var done = false
                while !done {
                    try context.charge(.workUnits)
                    var supplied = 0
                    for slot in slots where bindings[slot] >= 2 { supplied |= 1 << ((bindings[slot] - 2) / 2) }
                    let actual = supplied & required == required
                        ? try truth(function, bindings: bindings, count: count, context: &context) : target ^ 1
                    let inverted = actual != target && actual ^ MappingArithmetic.mask(count) == target
                    if supplied & required == required && (actual == target || (inverter != nil && inverted)) {
                        var inversions = inverted ? 1 : 0
                        for leaf in 0..<count {
                            if bindings.contains(3 + 2 * leaf) { inversions += 1 }
                        }
                        if inversions == 0 || inverter != nil {
                            let area = cell.area + Double(inversions) * (inverter?.area ?? 0)
                            guard area.isFinite else { throw .invalidModel("Mapping area overflows") }
                            let match = MappingMatch(cell: .init(ci), output: .init(output), bindings: bindings,
                                invertedOutput: inverted, area: area,
                                depth: 1 + (inverted ? inverter!.depth : 0) + (inversions > (inverted ? 1 : 0) ? inverter!.depth : 0))
                            if try preferable(match, to: best) { best = try retained(match, context: &context) }
                        }
                    }
                    var digit = 0
                    while digit < slots.count {
                        let pin = slots[digit]
                        bindings[pin] += 1
                        if inverter == nil && bindings[pin] >= 3 && bindings[pin] % 2 != 0 { bindings[pin] += 1 }
                        if bindings[pin] < 2 + 2 * count { break }
                        bindings[pin] = 0; digit += 1
                    }
                    done = digit == slots.count
                }
            }
        }
        return best
    }
    mutating func constant(_ value: Bool, context: inout LogicKernelContext) throws(LogicKernelError) -> MappingMatch? {
        var best: MappingMatch?
        for ci in 0..<library.cellCount {
            try context.charge(.workUnits)
            let cell = try library.cell(at: .init(ci))
            guard cell.state == nil else { continue }
            var inputless = true
            for pi in 0..<cell.pinCount {
                try context.charge(.workUnits)
                if try cell.pin(at: .init(pi)).direction == .input { inputless = false }
            }
            guard inputless else { continue }
            bindings.removeAll(keepingCapacity: true)
            for _ in 0..<cell.pinCount { try context.charge(.workUnits); bindings.append(0) }
            // Inputless cells use these output slots to retain exact constant values.
            for pi in 0..<cell.pinCount {
                guard let function = try cell.pin(at: .init(pi)).function else { throw .invalidModel("Tie output lost its function") }
                bindings[pi] = try truth(function, bindings: bindings, count: 0, context: &context) == 0 ? 0 : 1
            }
            for pi in 0..<cell.pinCount where bindings[pi] == (value ? 1 : 0) {
                try context.charge(.workUnits)
                let match = MappingMatch(cell: .init(ci), output: .init(pi), bindings: bindings,
                    invertedOutput: false, area: cell.area, depth: 1)
                if try preferable(match, to: best) { best = try retained(match, context: &context) }
            }
        }
        return best
    }
    mutating func sequential(control: BitStateControl, inverter: MappingMatch?, context: inout LogicKernelContext)
        throws(LogicKernelError) -> MappingMatch? {
        var best: MappingMatch?
        for ci in 0..<library.cellCount {
            let cell = try library.cell(at: .init(ci)); try context.charge(.workUnits)
            guard let definition = cell.state else { continue }
            let reset: BitReset?
            switch (control, definition.control) {
            case (.flipFlop(_, let edge, _, let r), .flipFlop(_, let rising)):
                guard (edge == .rising) == rising else { continue }; reset = r
            case (.latch(_, let active, let r), .latch(_, let high)):
                guard active == high else { continue }; reset = r
            default: continue
            }
            if let r = reset {
                guard r.kind == .asynchronous, let actual = definition.asynchronousReset,
                      r.activeHigh == actual.activeHigh, r.value == actual.value else { continue }
            } else if definition.asynchronousReset != nil { continue }
            var slots: [Int] = []
            for pi in 0..<cell.pinCount where try cell.pin(at: .init(pi)).direction == .input {
                if pi != definition.control.pin.rawValue && pi != definition.asynchronousReset?.pin.rawValue { slots.append(pi) }
            }
            guard slots.count <= maximumInputs else { continue }
            bindings.removeAll(keepingCapacity: true)
            for _ in 0...cell.pinCount { bindings.append(0) }
            // D, current Q, control and reset are independent exhaustive variables.
            bindings[cell.pinCount] = 4
            bindings[definition.control.pin.rawValue] = 6
            if let r = definition.asynchronousReset { bindings[r.pin.rawValue] = 8 }
            var done = false
            while !done {
                try context.charge(.workUnits)
                if try truth(definition.nextState, bindings: bindings, count: 4, context: &context) == MappingArithmetic.variable(0, count: 4) {
                    for output in 0..<cell.pinCount {
                        try context.charge(.workUnits)
                        guard let function = try cell.pin(at: .init(output)).function else { continue }
                        let actual = try truth(function, bindings: bindings, count: 4, context: &context)
                        let q = MappingArithmetic.variable(1, count: 4)
                        let inverted = actual != q && actual ^ MappingArithmetic.mask(4) == q
                        guard actual == q || (inverted && inverter != nil) else { continue }
                        let match = MappingMatch(cell: .init(ci), output: .init(output), bindings: bindings,
                            invertedOutput: inverted, area: cell.area + (inverted ? inverter!.area : 0),
                            depth: inverted ? inverter!.depth : 0)
                        if try preferable(match, to: best) { best = try retained(match, context: &context) }
                    }
                }
                var digit = 0
                while digit < slots.count {
                    let pin = slots[digit]; bindings[pin] += 1
                    // Ties and positive D suffice after synchronous control expansion.
                    if bindings[pin] < 3 { break }
                    bindings[pin] = 0; digit += 1
                }
                done = digit == slots.count
            }
        }
        return best
    }
}
