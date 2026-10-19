import CircuiteFoundation
import CircuiteFoundationCrypto
import LogicIR
import LogicKernelCore
import TimingCore

public struct NativeLogicTechnologyLibraryCompiler: LogicTechnologyLibraryCompiling {
    internal let digester: any ContentDigesting
    public init(digester: any ContentDigesting = SHA256ContentDigester()) { self.digester = digester }

    public func compile(_ source: borrowing OwnedLibertySource, identity: ArtifactID,
                        options: borrowing LogicLibraryCompilationOptions, context: inout LogicKernelContext)
        throws(LogicLibraryCompilationError) -> LogicLibraryCompilation {
        try verifySource(source, identity: identity, context: &context)
        let normal = try LogicLibraryNormalPower.prepare(source: source, identity: identity, options: options, context: &context)
        do throws(LogicKernelError) {
            return try compileCells(source, identity: identity, options: options, normal: normal, context: &context)
        } catch { throw .kernel(error) }
    }

    internal enum Binding { case pin(Int), state(inverted: Bool), output }
    internal struct Plan {
        let control: LogicCellStateDefinition.Control?
        let reset: LogicCellStateDefinition.AsynchronousReset?
        let data: LibertyBooleanFunctionFacts?
    }

    private func compileCells(_ source: borrowing OwnedLibertySource, identity: ArtifactID,
                              options: borrowing LogicLibraryCompilationOptions, normal: borrowing LogicLibraryNormalPower,
                              context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicLibraryCompilation {
        var count: UInt64 = 0
        var totalPins = 0
        for index in source.cells.indices {
            try context.charge(.workUnits)
            let n = source.cells[index].pins.count
            let pins = totalPins.addingReportingOverflow(n)
            let entities = count.addingReportingOverflow(UInt64(n) + 1)
            guard !pins.overflow, !entities.overflow else { throw .invalidInput("Library source capacity overflows") }
            totalPins = pins.partialValue; count = entities.partialValue
        }
        guard count <= UInt64.max - options.firstEntityID.rawValue + 1 else {
            throw .invalidInput("Library canonical identity range exhausted")
        }
        let reportPayload = UInt64(source.cells.count).multipliedReportingOverflow(by: UInt64(MemoryLayout<LogicLibraryCellEligibility>.stride))
        let namesPayload = UInt64(source.cells.count).multipliedReportingOverflow(by: UInt64(MemoryLayout<String>.stride))
        let bytes = reportPayload.partialValue.addingReportingOverflow(namesPayload.partialValue)
        let total = bytes.partialValue.addingReportingOverflow(UInt64(MemoryLayout<(ArtifactID, LogicTechnologyLibrary?, [LogicLibraryCellEligibility], LogicLibraryNormalPower, [LogicOperatingConditionPolicy])>.stride))
        guard !reportPayload.overflow, !namesPayload.overflow, !bytes.overflow, !total.overflow else {
            throw .invalidInput("Library report storage overflows")
        }
        _ = try context.reserveStorage(byteCount: total.partialValue)
        var reports: [LogicLibraryCellEligibility] = []; reports.reserveCapacity(source.cells.count)
        var names = Set<String>(); names.reserveCapacity(source.cells.count)
        if source.cells.isEmpty { return .init(storage: .init(source: identity, library: nil, cells: reports,
            normalPower: copy normal, policies: options.operatingConditionPolicies)) }
        var builder = try LogicTechnologyLibraryBuilder(cellCapacity: source.cells.count, totalPinCapacity: totalPins, context: &context)
        var offset: UInt64 = 0
        var eligible = 0
        for index in source.cells.indices {
            let cell = source.cells[index]
            try context.charge(.workUnits, amount: UInt64(cell.name.utf8.count) + 1)
            _ = try context.reserveStorage(byteCount: UInt64(cell.name.utf8.count))
            guard names.insert(cell.name).inserted else { throw .invalidModel("Duplicate original Liberty cell name") }
            let rawID = options.firstEntityID.rawValue + offset
            let cellID = try entity(rawID)
            offset += UInt64(cell.pins.count) + 1
            guard cell.byteOffset >= 0, UInt64(cell.byteOffset) <= identity.byteCount else {
                throw .invalidModel("Liberty cell source position is outside the verified artifact")
            }
            let origin = try LogicKernelSourceRange(artifactID: identity, byteRange: UInt64(cell.byteOffset)..<UInt64(cell.byteOffset))
            var namespace: [String: Binding] = [:]
            let requirement = normal.requirements[cell.name]
            try context.charge(.workUnits, amount: UInt64(normal.policyOutcomes.count))
            let conditioned = normal.policyOutcomes.contains { $0.receipt.cell == cell.name }
            let inspected = try inspect(cell, normalPower: requirement, conditioned: conditioned, namespace: &namespace, context: &context)
            let outcome: LogicLibraryCellEligibility.Outcome
            switch inspected {
            case .failure(let reason):
                _ = try context.reserveStorage(byteCount: reason.retainedTextByteCount)
                outcome = .ineligible(reason)
            case .success(let plan):
                let definition = try build(cell, cellID: cellID, plan: plan, namespace: namespace, context: &context)
                let dense = try builder.append(definition, context: &context)
                eligible += 1
                outcome = .eligible(dense)
            }
            reports.append(.init(cellID: cellID, name: cell.name, origin: origin, outcome: outcome))
        }
        let library = eligible == 0 ? nil : try builder.finish(source: identity, context: &context)
        return .init(storage: .init(source: identity, library: library, cells: reports,
            normalPower: copy normal, policies: options.operatingConditionPolicies))
    }

    internal func entity(_ value: UInt64) throws(LogicKernelError) -> DesignEntityID {
        do { return try .init(rawValue: value) }
        catch { throw .invalidModel("Compiler generated an invalid canonical identity") }
    }

    private func build(_ cell: LibertySourceCell, cellID: DesignEntityID, plan: Plan,
                       namespace: borrowing [String: Binding], context: inout LogicKernelContext)
        throws(LogicKernelError) -> LogicTechnologyCell {
        let slots = cell.pins.count.addingReportingOverflow(plan.control == nil ? 0 : 1)
        guard !slots.overflow else { throw .invalidInput("Library function namespace overflows") }
        var builder = try LogicTechnologyCellBuilder(id: cellID, name: cell.name, pinCapacity: cell.pins.count, context: &context)
        for index in cell.pins.indices {
            try context.charge(.workUnits)
            let pin = cell.pins[index]
            let function: LogicBooleanFunction?
            if let source = pin.function, case .normalized(let facts) = source.content {
                function = try rebind(facts, namespace: namespace, pinCount: cell.pins.count, slots: slots.partialValue, context: &context)
            } else { function = nil }
            _ = try builder.append(.init(id: entity(cellID.rawValue + UInt64(index) + 1), name: pin.name,
                direction: pin.direction == .input ? .input : .output, function: function), context: &context)
        }
        let state: LogicCellStateDefinition?
        if let control = plan.control, let data = plan.data {
            state = .init(control: control, nextState: try rebind(data, namespace: namespace, pinCount: cell.pins.count,
                slots: slots.partialValue, context: &context), asynchronousReset: plan.reset)
        } else { state = nil }
        guard let area = cell.area else { throw .invalidModel("Admitted cell lost its explicit area") }
        return try builder.finish(area: area, state: state, context: &context)
    }
}
