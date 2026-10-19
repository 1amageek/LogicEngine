import LogicIR
import LogicKernelCore
import TimingCore

extension NativeLogicTechnologyLibraryCompiler {
    internal func rebind(_ facts: LibertyBooleanFunctionFacts, namespace: borrowing [String: Binding],
                         pinCount: Int, slots: Int, context: inout LogicKernelContext) throws(LogicKernelError) -> LogicBooleanFunction {
        let capacity = facts.operations.count.multipliedReportingOverflow(by: 2)
        let bytes = UInt64(facts.operations.count).multipliedReportingOverflow(by: UInt64(MemoryLayout<LogicBooleanNodeIndex>.stride))
        guard !capacity.overflow, !bytes.overflow, capacity.partialValue > 0 else { throw .invalidModel("Cell function rebuilding capacity is invalid") }
        _ = try context.reserveStorage(byteCount: bytes.partialValue)
        var remapped: [LogicBooleanNodeIndex] = []; remapped.reserveCapacity(facts.operations.count)
        var builder = try LogicBooleanFunctionBuilder(inputCount: slots, nodeCapacity: capacity.partialValue, context: &context)
        func reference(_ index: LogicBooleanNodeIndex) throws(LogicKernelError) -> LogicBooleanNodeIndex {
            guard remapped.indices.contains(index.rawValue) else { throw .invalidModel("Original Boolean edge is not a prior node") }
            return remapped[index.rawValue]
        }
        for operation in facts.operations {
            try context.charge(.workUnits)
            let rebound: LogicBooleanOperation
            switch operation {
            case .constant(let value): rebound = .constant(value)
            case .input(let slot):
                guard facts.symbols.indices.contains(slot) else { throw .invalidModel("Original function symbol is out of range") }
                let name = facts.symbols[slot]
                try context.charge(.workUnits, amount: UInt64(name.utf8.count) + 1)
                guard let binding = namespace[name] else { throw .invalidModel("Admitted function lost its symbol binding") }
                switch binding {
                case .pin(let pin): rebound = .input(pin)
                case .state(let inverted):
                    if inverted {
                        let q = try builder.append(.input(pinCount), context: &context)
                        rebound = .invert(q)
                    } else { rebound = .input(pinCount) }
                case .output: throw .invalidModel("Admitted function references a physical output")
                }
            case .invert(let a): rebound = .invert(try reference(a))
            case .and(let a, let b): rebound = .and(try reference(a), try reference(b))
            case .or(let a, let b): rebound = .or(try reference(a), try reference(b))
            case .xor(let a, let b): rebound = .xor(try reference(a), try reference(b))
            }
            remapped.append(try builder.append(rebound, context: &context))
        }
        return try builder.finish(output: reference(facts.output), context: &context)
    }
}
