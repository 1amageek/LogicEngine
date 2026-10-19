import LogicIR
import LogicKernelCore
import TimingCore

extension NativeLogicTechnologyLibraryCompiler {
    internal func inspect(_ cell: LibertySourceCell, normalPower: LibertyNormalPowerRequirements?, conditioned: Bool,
                          namespace: inout [String: Binding], context: inout LogicKernelContext)
        throws(LogicKernelError) -> Result<Plan, LogicLibraryCellEligibility.Reason> {
        try context.charge(.workUnits)
        guard !cell.name.isEmpty else { return .failure(.invalidCellName) }
        if cell.dontUse == true { return .failure(.dontUse) }
        if let group = cell.unsupportedFunctionalGroups.first { return .failure(.unsupportedFunctionalGroup(group)) }
        guard let normalPower else { throw .invalidModel("Missing source normal-power requirements") }
        if normalPower.requiresCondition && !conditioned {
            return .failure(normalPower.functionOrigins.isEmpty ? .requiresOperatingConditions : .unsupportedPowerDown)
        }
        guard let area = cell.area else { return .failure(.missingArea) }
        guard area.isFinite, area >= 0 else { return .failure(.invalidArea) }
        guard cell.sequential.count <= 1 else { return .failure(.unsupportedStateDefinition) }
        let capacity = cell.pins.count.addingReportingOverflow(2)
        guard !capacity.overflow else { throw .invalidInput("Cell namespace capacity overflows") }
        let bytes = UInt64(capacity.partialValue).multipliedReportingOverflow(by: UInt64(MemoryLayout<(String, Binding)>.stride))
        guard !bytes.overflow else { throw .invalidInput("Cell namespace storage overflows") }
        _ = try context.reserveStorage(byteCount: bytes.partialValue)
        namespace.reserveCapacity(capacity.partialValue)
        var outputs = 0
        for index in cell.pins.indices {
            let pin = cell.pins[index]
            try context.charge(.workUnits, amount: UInt64(pin.name.utf8.count) + 1)
            guard !pin.name.isEmpty else { return .failure(.duplicatePin(pin.name)) }
            guard namespace[pin.name] == nil else { return .failure(.duplicatePin(pin.name)) }
            guard pin.direction == .input || pin.direction == .output else { return .failure(.unsupportedDirection(pin.name)) }
            if pin.threeState != nil || pin.xFunction != nil || pin.stateFunction != nil {
                return .failure(.unsupportedPinExtension(pin.name))
            }
            if pin.direction == .input {
                guard pin.function == nil else { return .failure(.unexpectedInputFunction(pin.name)) }
                namespace[pin.name] = .pin(index)
            } else {
                guard pin.function != nil else { return .failure(.missingOutputFunction(pin.name)) }
                outputs += 1; namespace[pin.name] = .output
            }
        }
        guard outputs > 0 else { return .failure(.noOutput) }
        var data: LibertyBooleanFunctionFacts?
        var control: LogicCellStateDefinition.Control?
        var reset: LogicCellStateDefinition.AsynchronousReset?
        if let state = cell.sequential.first {
            guard state.variables.count == 2, state.variables[0] != state.variables[1],
                  state.additionalControl == nil, state.clear == nil || state.preset == nil,
                  state.clearPresetVariable1 == nil, state.clearPresetVariable2 == nil,
                  let next = state.data, let clock = state.control else { return .failure(.unsupportedStateDefinition) }
            for index in state.variables.indices {
                let name = state.variables[index]
                try context.charge(.workUnits, amount: UInt64(name.utf8.count) + 1)
                guard !name.isEmpty, namespace[name] == nil else { return .failure(.ambiguousStateSymbol(name)) }
                namespace[name] = .state(inverted: index == 1)
            }
            switch try inspectFunction(next, namespace: namespace, context: &context) {
            case .failure(let issue): return .failure(issue)
            case .success(let facts): data = facts
            }
            switch try literal(clock, namespace: namespace, context: &context) {
            case .failure(let issue): return .failure(issue)
            case .success(let literal):
                control = state.kind == .flipFlop ? .flipFlop(clock: .init(literal.pin), risingEdge: literal.positive)
                    : .latch(gate: .init(literal.pin), activeHigh: literal.positive)
            }
            if let asynchronous = state.clear ?? state.preset {
                switch try literal(asynchronous, namespace: namespace, context: &context) {
                case .failure(let issue): return .failure(issue)
                case .success(let literal):
                    guard control?.pin.rawValue != literal.pin else { return .failure(.unsupportedControl) }
                    reset = .init(pin: .init(literal.pin), activeHigh: literal.positive, value: state.preset != nil)
                }
            }
        }
        for pin in cell.pins {
            try context.charge(.workUnits)
            if let function = pin.function, case .failure(let reason) = try inspectFunction(function, namespace: namespace, context: &context) {
                return .failure(reason)
            }
        }
        return .success(.init(control: control, reset: reset, data: data))
    }

    private func inspectFunction(_ source: LibertySourceFunction, namespace: borrowing [String: Binding],
                                 context: inout LogicKernelContext)
        throws(LogicKernelError) -> Result<LibertyBooleanFunctionFacts, LogicLibraryCellEligibility.Reason> {
        guard case .normalized(let facts) = source.content else {
            if case .unsupported(let issue) = source.content { return .failure(.unsupportedFunction(issue)) }
            throw .invalidModel("Source function publication is invalid")
        }
        for name in facts.symbols {
            try context.charge(.workUnits, amount: UInt64(name.utf8.count) + 1)
            guard let binding = namespace[name] else { return .failure(.unknownSymbol(name)) }
            if case .output = binding { return .failure(.outputPinReference(name)) }
        }
        return .success(facts)
    }

    private func literal(_ source: LibertySourceFunction, namespace: borrowing [String: Binding], context: inout LogicKernelContext)
        throws(LogicKernelError) -> Result<(pin: Int, positive: Bool), LogicLibraryCellEligibility.Reason> {
        let facts: LibertyBooleanFunctionFacts
        switch try inspectFunction(source, namespace: namespace, context: &context) {
        case .failure(let issue): return .failure(issue)
        case .success(let value): facts = value
        }
        var node = facts.output.rawValue
        var positive = true
        while true {
            try context.charge(.workUnits)
            guard facts.operations.indices.contains(node) else { throw .invalidModel("Invalid original control function node") }
            switch facts.operations[node] {
            case .input(let slot):
                guard facts.symbols.indices.contains(slot) else { throw .invalidModel("Invalid original control symbol") }
                if case .pin(let pin) = namespace[facts.symbols[slot]] { return .success((pin, positive)) }
                return .failure(.unsupportedControl)
            case .invert(let previous):
                guard previous.rawValue >= 0, previous.rawValue < node else { throw .invalidModel("Invalid original control edge") }
                node = previous.rawValue; positive.toggle()
            default: return .failure(.unsupportedControl)
            }
        }
    }
}
