import LogicIR
import LogicKernelCore
import LogicLowering

enum WordLoweringReference {
    static func lower(_ rtl: borrowing ElaboratedRTL) throws -> BitLogicDesign {
        var context = try RTLFixture.context()
        let wordKernel: any LogicWordLowering = NativeLogicWordLowering()
        let word = try wordKernel.lower(rtl, context: &context)
        return try NativeLogicBitLowering().lower(word, context: &context)
    }
    static func bits(_ value: Int, width: Int) -> [Bool] { (0..<width).map { value & (1 << $0) != 0 } }
    static func integer(_ bits: [Bool]) -> Int { bits.enumerated().reduce(0) { $0 | ($1.element ? 1 << $1.offset : 0) } }

    // Gate-level reference reads only the actual published bit circuit, never
    // procedural metadata or the original RTL operation being checked.
    static func run(_ graph: borrowing BitLogicDesign, inputs: [[Bool]], state: [Bool] = []) throws -> (outputs: [[Bool]], next: [Bool]) {
        graph.withTables { nodes, operands, ports, bindings, states, order in
            var values = [Bool](repeating: false, count: nodes.count); var input = 0
            for index in ports.indices where ports[index].direction == .input {
                for offset in 0..<ports[index].bits.count { values[bindings[ports[index].bits.lowerBound + offset].rawValue] = inputs[input][offset] }
                input += 1
            }
            for ordinal in order.indices {
                let index = order[ordinal].rawValue; let node = nodes[index]
                func operand(_ offset: Int) -> Bool { values[operands[node.operands.lowerBound + offset].rawValue] }
                switch node.operation {
                case .input: break
                case .constant(let bit): values[index] = bit
                case .state(let bit): values[index] = state[bit.rawValue]
                case .buffer: values[index] = operand(0)
                case .invert: values[index] = !operand(0)
                case .and: values[index] = operand(0) && operand(1)
                case .or: values[index] = operand(0) || operand(1)
                case .xor: values[index] = operand(0) != operand(1)
                case .select: values[index] = operand(0) ? operand(1) : operand(2)
                }
            }
            var next = state
            for index in states.indices {
                let entry = states[index]; let reset: BitReset?
                switch entry.control {
                case .flipFlop(_, _, let enable, let selectedReset):
                    if enable == nil || values[enable!.rawValue] { next[index] = values[entry.next.rawValue] }
                    reset = selectedReset
                case .latch(let gate, let high, let selectedReset):
                    if values[gate.rawValue] == high { next[index] = values[entry.next.rawValue] }
                    reset = selectedReset
                }
                if let reset, values[reset.signal.rawValue] == reset.activeHigh { next[index] = reset.value }
            }
            return (ports.indices.filter { ports[$0].direction == .output }.map { port in
                ports[port].bits.map { values[bindings[$0].rawValue] }
            }, next)
        }
    }
}
