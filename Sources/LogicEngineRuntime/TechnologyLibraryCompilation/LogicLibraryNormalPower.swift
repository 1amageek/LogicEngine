import CircuiteFoundation
import LogicKernelCore
import TimingCore

internal struct LogicLibraryNormalPower: Sendable {
    let requirements: [String: LibertyNormalPowerRequirements]
    let policyOutcomes: [CheckedLibertyNormalPower]
    let unconditional: [String: CheckedLibertyNormalPower]

    static func prepare(source: borrowing OwnedLibertySource, identity: ArtifactID,
                        options: borrowing LogicLibraryCompilationOptions, context: inout LogicKernelContext)
        throws(LogicLibraryCompilationError) -> Self {
        let validator: any LibertyNormalPowerValidating = LibertyNormalPowerValidator()
        var admission = LogicNormalPowerAdmission(sourceStorageCredit: options.sourceStorageCredit)
        var requirements: [String: LibertyNormalPowerRequirements] = [:]
        var unconditional: [String: CheckedLibertyNormalPower] = [:]
        var outcomes: [CheckedLibertyNormalPower] = []
        do {
            try reserve(source.cells.count, stride: MemoryLayout<(String, LibertyNormalPowerRequirements, CheckedLibertyNormalPower?)>.stride, context: &context)
            try reserve(options.operatingConditionPolicies.count, stride: MemoryLayout<CheckedLibertyNormalPower>.stride, context: &context)
            requirements.reserveCapacity(source.cells.count); unconditional.reserveCapacity(source.cells.count)
            outcomes.reserveCapacity(options.operatingConditionPolicies.count)
            for cell in source.cells {
                try context.charge(.workUnits)
                // These cells already have a functional exclusion. Explicit policies below still validate.
                if cell.dontUse == true || !cell.unsupportedFunctionalGroups.isEmpty { continue }
                let requirement = try validator.requirements(source: source, cell: cell.name) { work, states, bytes in
                    try admission.admit(work: work, stateSlots: states, sourceReservationBytes: bytes, context: &context)
                }
                requirements[cell.name] = requirement
                if !requirement.requiresCondition {
                    unconditional[cell.name] = try validator.validate(source: source, cell: cell.name, conditions: []) { work, states, bytes in
                        try admission.admit(work: work, stateSlots: states, sourceReservationBytes: bytes, context: &context)
                    }
                }
            }
            for index in options.operatingConditionPolicies.indices {
                let policy = options.operatingConditionPolicies[index]
                try context.charge(.workUnits, amount: UInt64(policy.cell.utf8.count) + 1)
                guard policy.library.id == identity, !policy.cell.isEmpty,
                      policy.library.descriptor.format == .liberty, policy.cornerID != "" else {
                    throw LogicKernelError.invalidInput("Foreign or incomplete source-cell operating policy")
                }
                for prior in options.operatingConditionPolicies[..<index] {
                    try context.charge(.workUnits)
                    guard prior.library == policy.library,
                          prior.cell != policy.cell || prior.cornerID != policy.cornerID else {
                        throw LogicKernelError.invalidInput("Conflicting library reference or duplicate operating policy")
                    }
                }
                outcomes.append(try validator.validate(source: source, cell: policy.cell, conditions: policy.conditions) { work, states, bytes in
                    try admission.admit(work: work, stateSlots: states, sourceReservationBytes: bytes, context: &context)
                })
            }
        } catch let error as LibertyNormalPowerError { throw .normalPower(error) }
        catch let error as LogicKernelError { throw .kernel(error) }
        catch { throw .normalPower(.resource(error)) }
        return .init(requirements: requirements, policyOutcomes: outcomes, unconditional: unconditional)
    }

    private static func reserve(_ count: Int, stride: Int, context: inout LogicKernelContext) throws(LogicKernelError) {
        let bytes = UInt64(count).multipliedReportingOverflow(by: UInt64(stride))
        guard !bytes.overflow else { throw .invalidInput("Normal-power host storage overflow") }
        _ = try context.reserveStorage(byteCount: bytes.partialValue)
    }
}
