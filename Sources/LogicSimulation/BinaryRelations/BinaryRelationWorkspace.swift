import LogicIR
import LogicKernelCore

internal struct BinaryRelationWorkspace: ~Copyable {
    var values: [Bool]
    var functions: [Bool]
    var stateForInstance: [Int]
    var outputs: [Bool]
    var actions: [LogicBinaryStateAction]
    var eventStates: [Bool]
    var previousControls: [Bool]
    private let outputCapacity: Int
    private var receipt: LogicStorageReservation?
    init(nodes: Int, functionNodes: Int, instances: Int, states: Int, outputCapacity: Int, context: inout LogicKernelContext) throws(LogicKernelError) {
        var bytes = UInt64(MemoryLayout<Self>.stride)
        for (count, stride) in [(nodes, MemoryLayout<Bool>.stride), (functionNodes, MemoryLayout<Bool>.stride),
                               (instances, MemoryLayout<Int>.stride), (states, MemoryLayout<LogicBinaryStateAction>.stride + 2 * MemoryLayout<Bool>.stride), (outputCapacity, MemoryLayout<Bool>.stride)] {
            let payload = UInt64(count).multipliedReportingOverflow(by: UInt64(stride))
            let sum = bytes.addingReportingOverflow(payload.partialValue)
            guard !payload.overflow, !sum.overflow else { throw .invalidInput("Binary relation storage overflows") }
            bytes = sum.partialValue
        }
        try context.require(.nodes, amount: UInt64(nodes))
        try context.require(.states, amount: UInt64(states))
        let reservation = try context.reserveStorage(byteCount: bytes)
        values = .init(repeating: false, count: nodes)
        functions = .init(repeating: false, count: functionNodes)
        stateForInstance = .init(repeating: -1, count: instances)
        outputs = []; outputs.reserveCapacity(outputCapacity)
        actions = []; actions.reserveCapacity(states)
        eventStates = .init(repeating: false, count: states); previousControls = .init(repeating: false, count: states)
        receipt = consume reservation
        self.outputCapacity = outputCapacity
    }
    mutating func release(context: inout LogicKernelContext) throws(LogicKernelError) {
        values = []; functions = []; stateForInstance = []; outputs = []; actions = []; eventStates = []; previousControls = []
        let reservation = receipt.take()
        if let reservation { try context.releaseStorage(reservation) }
    }
    borrowing func publish(context: inout LogicKernelContext) throws(LogicKernelError) -> LogicBinaryObservation {
        let actionBytes = UInt64(actions.count).multipliedReportingOverflow(by: UInt64(MemoryLayout<LogicBinaryStateAction>.stride))
        let total = actionBytes.partialValue.addingReportingOverflow(UInt64(outputCapacity) + LogicBinaryObservation.storageByteCount)
        guard !actionBytes.overflow, !total.overflow else { throw .invalidInput("Binary relation output overflows") }
        _ = try context.reserveStorage(byteCount: total.partialValue)
        try context.charge(.outputBytes, amount: total.partialValue)
        return .init(outputs: outputs, actions: actions)
    }
    mutating func function(_ function: LogicBooleanFunction, instance: MappedGateInstance,
                           pins: borrowing Span<MappedNetIndex>, state: Bool, context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        try function.withOperations { operations throws(LogicKernelError) in
            for index in operations.indices {
                try context.charge(.workUnits)
                switch operations[index] {
                case .constant(let value): functions[index] = value
                case .input(let slot): functions[index] = slot == instance.pins.count ? state : values[pins[instance.pins.lowerBound + slot].rawValue]
                case .invert(let a): functions[index] = !functions[a.rawValue]
                case .and(let a, let b): functions[index] = functions[a.rawValue] && functions[b.rawValue]
                case .or(let a, let b): functions[index] = functions[a.rawValue] || functions[b.rawValue]
                case .xor(let a, let b): functions[index] = functions[a.rawValue] != functions[b.rawValue]
                }
            }
            return functions[function.output.rawValue]
        }
    }
}
