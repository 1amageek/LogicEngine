import CircuiteFoundation
import LogicIR
import LogicKernelCore
import TimingCore

internal enum LogicOperatingConditionExpansion {
    static func scopes(_ request: LogicSynthesisRequest, context: inout LogicKernelContext) throws(LogicKernelError) -> [String?] {
        let count = request.operatingProcessScope?.cornerIDs.count ?? 1
        try reserve(count, stride: MemoryLayout<String?>.stride, context: &context)
        if let scope = request.operatingProcessScope {
            var result: [String?] = []; result.reserveCapacity(count)
            for corner in scope.cornerIDs { try context.charge(.workUnits); result.append(corner) }
            return result
        }
        return [nil]
    }

    static func qualify(_ mapped: borrowing MappedGateDesign, compilation: LogicLibraryCompilation,
                        libraryReference: ArtifactReference, corners: [String?], context: inout LogicKernelContext)
        throws(LogicOperatingConditionError) -> LogicCheckedOperatingConditions {
        do {
            guard let library = compilation.library, libraryReference.id == compilation.source,
                  !corners.isEmpty else { throw LogicOperatingConditionError.invalidInput("Missing compiled source or condition scope") }
            try requireSameLibrary(mapped.library, library, context: &context)
            let policies = compilation.operatingConditionPolicies
            for policy in policies {
                try context.charge(.workUnits)
                var contains = false
                for corner in corners { try context.charge(.workUnits); if corner == policy.cornerID { contains = true } }
                guard policy.library == libraryReference, contains else {
                    throw LogicOperatingConditionError.invalidInput("Operating policy has a foreign reference or corner")
                }
            }
            let capacity = mapped.instanceCount.multipliedReportingOverflow(by: corners.count)
            guard !capacity.overflow else { throw LogicOperatingConditionError.invalidInput("Condition expansion capacity overflow") }
            try reserve(capacity.partialValue, stride: MemoryLayout<LogicResolvedOperatingCondition>.stride, context: &context)
            try reserve(policies.count, stride: MemoryLayout<Bool>.stride + MemoryLayout<Int>.stride + MemoryLayout<LibertyNormalPowerReceipt>.stride, context: &context)
            var records: [LogicResolvedOperatingCondition] = []; records.reserveCapacity(capacity.partialValue)
            var used = [Bool](repeating: false, count: policies.count)
            try mapped.withTables { _, instances, _, _, _, _ in
                for index in instances.indices {
                    let instance = instances[index]
                    let cell = try mapped.library.cell(at: instance.cell)
                    guard let requirement = compilation.normalPower.requirements[cell.name] else {
                        throw LogicOperatingConditionError.invalidInput("Candidate cell lacks exact source requirements")
                    }
                    var digits = 1, number = index
                    while number >= 10 { try context.charge(.workUnits); digits += 1; number /= 10 }
                    _ = try context.reserveStorage(byteCount: UInt64(digits + 1))
                    let name = "i\(index)"
                    for corner in corners {
                        var policyIndex: Int?
                        for p in policies.indices {
                            try context.charge(.workUnits, amount: UInt64(cell.name.utf8.count) + 1)
                            if policies[p].cell == cell.name, policies[p].cornerID == corner {
                                guard policyIndex == nil else { throw LogicOperatingConditionError.invalidInput("Duplicate candidate condition") }
                                policyIndex = p
                            }
                        }
                        let checked: CheckedLibertyNormalPower
                        if let p = policyIndex { checked = compilation.normalPower.policyOutcomes[p]; used[p] = true }
                        else {
                            guard !requirement.requiresCondition, let unconditional = compilation.normalPower.unconditional[cell.name] else {
                                throw LogicOperatingConditionError.invalidInput("Selected source cell lacks complete operating conditions")
                            }
                            checked = unconditional
                        }
                        records.append(.init(instanceID: instance.id, interchangeName: name, cellID: cell.id, cellName: cell.name,
                            library: libraryReference, cornerID: corner, policyIndex: policyIndex, normalPower: checked.receipt))
                    }
                }
            }
            var unused: [Int] = []; unused.reserveCapacity(policies.count)
            var outcomes: [LibertyNormalPowerReceipt] = []; outcomes.reserveCapacity(policies.count)
            for index in policies.indices {
                try context.charge(.workUnits)
                if !used[index] { unused.append(index) }
                outcomes.append(compilation.normalPower.policyOutcomes[index].receipt)
            }
            return .init(receipt: .init(policies: policies, policyOutcomes: outcomes, records: records, unusedPolicyIndices: unused), compilation: compilation)
        } catch let error as LogicOperatingConditionError { throw error }
        catch let error as LogicKernelError { throw .kernel(error) }
        catch { throw .invalidInput(String(describing: error)) }
    }

    private static func reserve(_ count: Int, stride: Int, context: inout LogicKernelContext) throws(LogicKernelError) {
        let bytes = UInt64(count).multipliedReportingOverflow(by: UInt64(stride))
        guard !bytes.overflow else { throw .invalidInput("Condition storage overflow") }
        _ = try context.reserveStorage(byteCount: bytes.partialValue)
    }

    private static func requireSameLibrary(_ candidate: LogicTechnologyLibrary, _ expected: LogicTechnologyLibrary,
                                           context: inout LogicKernelContext) throws(LogicKernelError) {
        guard candidate.source == expected.source, candidate.cellCount == expected.cellCount else {
            throw .invalidInput("Candidate library differs from checked source")
        }
        for index in 0..<expected.cellCount {
            let a = try candidate.cell(at: .init(index)), b = try expected.cell(at: .init(index))
            try context.charge(.workUnits, amount: UInt64(a.name.utf8.count + b.name.utf8.count) + 1)
            guard a.id == b.id, a.name == b.name, a.area == b.area, a.pinCount == b.pinCount else {
                throw .invalidInput("Candidate source-cell identity differs")
            }
            for p in 0..<a.pinCount {
                let lhs = try a.pin(at: .init(p)), rhs = try b.pin(at: .init(p))
                try context.charge(.workUnits, amount: UInt64(lhs.name.utf8.count + rhs.name.utf8.count) + 1)
                guard lhs.id == rhs.id, lhs.name == rhs.name, lhs.direction == rhs.direction,
                      try same(lhs.function, rhs.function, context: &context) else { throw .invalidInput("Candidate pin/function differs from checked source") }
            }
            switch (a.state, b.state) {
            case (nil, nil): break
            case (.some(let lhs), .some(let rhs)):
                guard lhs.control == rhs.control, lhs.asynchronousReset == rhs.asynchronousReset,
                      try same(lhs.nextState, rhs.nextState, context: &context) else { throw .invalidInput("Candidate state differs from checked source") }
            default: throw .invalidInput("Candidate state presence differs from checked source")
            }
        }
    }

    private static func same(_ a: LogicBooleanFunction?, _ b: LogicBooleanFunction?, context: inout LogicKernelContext) throws(LogicKernelError) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (.some(let lhs), .some(let rhs)):
            guard lhs.inputCount == rhs.inputCount, lhs.output == rhs.output, lhs.nodeCount == rhs.nodeCount else { return false }
            return try lhs.withOperations { left throws(LogicKernelError) in
                try rhs.withOperations { right throws(LogicKernelError) in
                    for index in left.indices {
                        try context.charge(.workUnits)
                        if left[index] != right[index] { return false }
                    }
                    return true
                }
            }
        default: return false
        }
    }
}
