import LogicKernelCore
import STAEngine
import TimingCore

/// Original reload predicates with explicit scans; no decoded metric becomes proof.
internal enum LogicReloadTimingValidation {
    static func validate(_ result: STAExecutionResult, request: STARequest,
        constraints: LogicSynthesisTimingConstraints,
        resources: any LibertySourceResourceAccounting) throws {
        try resources.check()
        guard result.status == .completed else { throw LogicRuntimeError.unsupported("STA did not complete") }
        try work(result.runID, request.runID, resources: resources)
        guard result.runID == request.runID,
              result.evidence.provenance.inputs.count == request.inputs.count else { throw invalid() }
        for index in request.inputs.indices {
            try resources.chargeWork(1)
            guard result.evidence.provenance.inputs[index] == request.inputs[index] else { throw invalid() }
        }
        guard try equalSet(result.payload.analyzedCorners, constraints.cornerIDs, resources: resources),
              try equalSet(result.payload.analyzedModes, constraints.modeIDs, resources: resources),
              result.payload.processSelection != nil, let configuration = result.payload.effectiveConfiguration,
              configuration.characterizationPolicy == .requireObservedConditions else { throw invalid() }
        guard configuration.characterizationBindings.count == constraints.characterizationBindings.count else { throw invalid() }
        for index in constraints.characterizationBindings.indices {
            let lhs = configuration.characterizationBindings[index], rhs = constraints.characterizationBindings[index]
            try work(lhs.cornerID, rhs.cornerID, resources: resources)
            try work(lhs.conditionName, rhs.conditionName, resources: resources)
            guard lhs == rhs else { throw invalid() }
        }
        // The original request initializer rejects duplicate keys. Select its
        // lexicographic canonical order without creating unadmitted sort tables.
        guard configuration.operatingSupplyAssumptions.count == request.operatingSupplyAssumptions.count else { throw invalid() }
        var prior: Int?
        for actual in configuration.operatingSupplyAssumptions {
            var next: Int?
            for index in request.operatingSupplyAssumptions.indices {
                try resources.check(); try resources.chargeWork(1)
                let candidate = request.operatingSupplyAssumptions[index]
                if let prior, try !less(request.operatingSupplyAssumptions[prior], candidate, resources: resources) { continue }
                if let selected = next {
                    if try less(candidate, request.operatingSupplyAssumptions[selected], resources: resources) { next = index }
                } else { next = index }
            }
            guard let next else { throw invalid() }
            let expected = request.operatingSupplyAssumptions[next]
            try work(actual.instance, expected.instance, resources: resources)
            try work(actual.cell, expected.cell, resources: resources)
            try work(actual.cornerID, expected.cornerID, resources: resources)
            try work(actual.pin, expected.pin, resources: resources)
            try work(actual.sourcePGType, expected.sourcePGType, resources: resources)
            try resources.chargeWork(2 * 152)
            try work(actual.library.digest.hexadecimalValue, expected.library.digest.hexadecimalValue, resources: resources)
            try work(actual.library.descriptor.role.rawValue, expected.library.descriptor.role.rawValue, resources: resources)
            try work(actual.library.descriptor.kind.rawValue, expected.library.descriptor.kind.rawValue, resources: resources)
            try work(actual.library.descriptor.format.rawValue, expected.library.descriptor.format.rawValue, resources: resources)
            guard actual == expected else { throw invalid() }
            prior = next
        }
        try work(result.payload.provenance.designDigest, request.design.digest.hexadecimalValue, resources: resources)
        try work(result.payload.provenance.constraintDigest, request.constraints.digest.hexadecimalValue, resources: resources)
        try work(result.payload.provenance.pdkDigest, request.pdkManifest.digest.hexadecimalValue, resources: resources)
        guard result.payload.provenance.designDigest == request.design.digest.hexadecimalValue,
              result.payload.provenance.constraintDigest == request.constraints.digest.hexadecimalValue,
              result.payload.provenance.pdkDigest == request.pdkManifest.digest.hexadecimalValue,
              result.payload.provenance.libraryDigests.count == request.libraries.count else { throw invalid() }
        for index in request.libraries.indices {
            try work(result.payload.provenance.libraryDigests[index], request.libraries[index].artifact.digest.hexadecimalValue,
                resources: resources)
            guard result.payload.provenance.libraryDigests[index] == request.libraries[index].artifact.digest.hexadecimalValue else { throw invalid() }
        }
        try slack(constraints.minimumSetupSlack, actual: result.payload.worstSetupSlack, kind: .setup,
            result: result, constraints: constraints, resources: resources)
        try slack(constraints.minimumHoldSlack, actual: result.payload.worstHoldSlack, kind: .hold,
            result: result, constraints: constraints, resources: resources)
        try resources.check()
    }

    private static func slack(_ required: Double?, actual: Double?, kind: STAAnalysisKind,
        result: STAExecutionResult, constraints: LogicSynthesisTimingConstraints,
        resources: any LibertySourceResourceAccounting) throws {
        guard let required else { return }
        for endpoint in result.payload.unconstrainedEndpoints {
            try resources.check(); try resources.chargeWork(1)
            guard !(endpoint.unconstrainedChecks?.contains(kind) ?? true) else {
                throw LogicRuntimeError.unsupported("Required slack has unconstrained endpoints")
            }
        }
        if let actual {
            guard actual.isFinite else { throw LogicRuntimeError.unsupported("Required slack is nonfinite") }
            guard actual >= required else { throw LogicRuntimeError.constraint("Candidate slack fails the required minimum") }
            return
        }
        var count = 0
        for endpoint in result.payload.endpoints {
            try resources.check(); try resources.chargeWork(1)
            let relevant = endpoint.staticChecks?.contains(kind) == true || endpoint.excludedChecks?.contains(kind) == true
                || (kind == .setup ? endpoint.setupSlack != nil : endpoint.holdSlack != nil)
            if relevant {
                count += 1
                guard (endpoint.staticValue != nil && endpoint.staticChecks?.contains(kind) == true)
                    || endpoint.excludedChecks?.contains(kind) == true else { throw missing() }
            }
        }
        guard count > 0 else { throw missing() }
        for corner in constraints.cornerIDs {
            for mode in constraints.modeIDs {
                var found = false
                for endpoint in result.payload.endpoints {
                    try resources.check(); try resources.chargeWork(1)
                    let relevant = endpoint.staticChecks?.contains(kind) == true || endpoint.excludedChecks?.contains(kind) == true
                        || (kind == .setup ? endpoint.setupSlack != nil : endpoint.holdSlack != nil)
                    if relevant {
                        try work(endpoint.cornerID, corner, resources: resources)
                        try work(endpoint.modeID, mode, resources: resources)
                        if endpoint.cornerID == corner && endpoint.modeID == mode { found = true; break }
                    }
                }
                guard found else { throw missing() }
            }
        }
    }

    private static func equalSet(_ lhs: [String], _ rhs: [String],
        resources: any LibertySourceResourceAccounting) throws -> Bool {
        for value in lhs {
            var found = false
            for candidate in rhs {
                try work(value, candidate, resources: resources)
                if value == candidate { found = true; break }
            }
            if !found { return false }
        }
        for value in rhs {
            var found = false
            for candidate in lhs {
                try work(value, candidate, resources: resources)
                if value == candidate { found = true; break }
            }
            if !found { return false }
        }
        return true
    }
    private static func less(_ lhs: STAOperatingSupplyAssumption, _ rhs: STAOperatingSupplyAssumption,
        resources: any LibertySourceResourceAccounting) throws -> Bool {
        try work(lhs.cornerID, rhs.cornerID, resources: resources)
        if lhs.cornerID != rhs.cornerID { return lhs.cornerID < rhs.cornerID }
        try work(lhs.instance, rhs.instance, resources: resources)
        if lhs.instance != rhs.instance { return lhs.instance < rhs.instance }
        try work(lhs.pin, rhs.pin, resources: resources)
        return lhs.pin < rhs.pin
    }
    private static func work(_ lhs: String?, _ rhs: String,
        resources: any LibertySourceResourceAccounting) throws {
        if let lhs { try work(lhs, rhs, resources: resources) }
        else { try resources.check(); try resources.chargeWork(1) }
    }
    private static func work(_ lhs: String, _ rhs: String,
        resources: any LibertySourceResourceAccounting) throws {
        let bytes = UInt64(lhs.utf8.count).addingReportingOverflow(UInt64(rhs.utf8.count))
        let total = bytes.partialValue.addingReportingOverflow(1)
        guard !bytes.overflow, !total.overflow else { throw LibertySourceError.arithmeticOverflow }
        try resources.check(); try resources.chargeWork(total.partialValue); try resources.check()
    }
    private static func invalid() -> LogicKernelError { .invalidInput("STA did not establish the exact required design/corner/condition analysis") }
    private static func missing() -> LogicRuntimeError { .unsupported("Required slack is unmeasured without complete static or excluded coverage") }
}
