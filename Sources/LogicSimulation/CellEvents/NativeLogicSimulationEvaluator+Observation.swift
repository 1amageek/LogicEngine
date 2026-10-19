import LogicIR
import LogicKernelCore

extension NativeLogicSimulationEvaluator {
    internal func observe(_ design: borrowing MappedGateDesign, time: UInt64, state: inout LogicSimulationState,
                          context: inout LogicKernelContext) throws(LogicKernelError) -> LogicObservation {
        try design.withTables { _, _, _, ports, bits, _ throws(LogicKernelError) in
            let bytes = UInt64(ports.count).multipliedReportingOverflow(by: UInt64(MemoryLayout<LogicObservation.Output>.stride))
            guard !bytes.overflow else { throw .invalidInput("Observation capacity overflows") }
            let total = bytes.partialValue.addingReportingOverflow(UInt64(MemoryLayout<(UInt64, [LogicObservation.Output])>.stride))
            guard !total.overflow else { throw .invalidInput("Observation metadata overflows") }
            _ = try context.reserveStorage(byteCount: total.partialValue)
            var outputs: [LogicObservation.Output] = []; outputs.reserveCapacity(ports.count)
            for index in ports.indices {
                try context.charge(.workUnits)
                let port = ports[index]
                guard port.direction == .output else { continue }
                let width = try LogicBitWidth(port.bits.count)
                let payload = UInt64(width.wordCount).multipliedReportingOverflow(by: 16)
                guard !payload.overflow else { throw .invalidInput("Observation value capacity overflows") }
                try context.charge(.outputBytes, amount: payload.partialValue)
                _ = try context.reserveStorage(byteCount: payload.partialValue)
                var values = [UInt64](repeating: 0, count: width.wordCount)
                var unknowns = [UInt64](repeating: 0, count: width.wordCount)
                for bit in 0..<width.value {
                    try context.charge(.workUnits)
                    let value = state.values[bits[port.bits.lowerBound + bit].rawValue].rawValue
                    values[bit / 64] |= UInt64(value & 1) << (bit % 64)
                    unknowns[bit / 64] |= UInt64((value >> 1) & 1) << (bit % 64)
                }
                let value = try LogicFourStateVector(width: width, valueWords: values, unknownWords: unknowns)
                outputs.append(.init(portID: port.id, portIndex: index, value: value))
            }
            return .init(time: time, outputs: outputs)
        }
    }
}
