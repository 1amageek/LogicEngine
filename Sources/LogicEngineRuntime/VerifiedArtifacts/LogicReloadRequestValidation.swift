import LogicKernelCore

/// The existing request predicates with metered scans and no validation Sets/maps.
internal enum LogicReloadRequestValidation {
    static func validate(_ request: LogicSynthesisRequest,
                         context: inout LogicKernelContext) throws(LogicKernelError) {
        try context.checkpoint()
        guard request.schemaVersion == LogicSynthesisRequest.currentSchemaVersion,
              !request.runID.isEmpty, !request.sources.isEmpty, !request.top.isEmpty,
              !request.roots.isEmpty, request.library.descriptor.format == .liberty else {
            throw .invalidInput("Invalid actual-cell synthesis request or schema")
        }
        for byte in request.runID.utf8 {
            try context.charge(.workUnits)
            guard (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
                || (byte >= 48 && byte <= 57) || byte == 45 || byte == 95 else {
                throw .invalidInput("Invalid actual-cell synthesis request or schema")
            }
        }
        for index in request.sources.indices {
            for prior in 0..<index {
                guard try !LogicReloadComparison.string(request.sources[index].logicalName,
                    request.sources[prior].logicalName, context: &context) else {
                    throw .invalidInput("Invalid actual-cell synthesis request or schema")
                }
            }
        }
        for index in request.roots.indices {
            for prior in 0..<index {
                guard try !LogicReloadComparison.string(request.roots[index], request.roots[prior], context: &context) else {
                    throw .invalidInput("Invalid actual-cell synthesis request or schema")
                }
            }
            var found = false
            for source in request.sources {
                if try LogicReloadComparison.string(request.roots[index], source.logicalName, context: &context) {
                    found = true; break
                }
            }
            guard found else { throw .invalidInput("Invalid actual-cell synthesis request or schema") }
        }
        let limits = request.limits
        guard limits.maximumInputBytes > 0, limits.maximumOutputBytes > 0,
              limits.timeoutNanoseconds > 0, limits.maximumTokens > 0,
              limits.maximumTableEntries > 0, limits.maximumNesting > 0 else {
            throw .invalidInput("Host byte/time/syntax capacities must be positive")
        }
        var resourceCount = 0
        for resource in LogicResource.allCases {
            try context.charge(.workUnits)
            guard let maximum = limits.kernelMaximums[resource.rawValue], maximum > 0 else {
                throw .invalidInput("Every resource requires an explicit positive limit")
            }
            resourceCount += 1
        }
        guard resourceCount == limits.kernelMaximums.count else { throw .invalidInput("Unknown kernel resource limits") }
        if let scope = request.operatingProcessScope {
            guard !scope.processID.isEmpty, !scope.pdkVersion.isEmpty,
                  !scope.cornerIDs.isEmpty, !scope.libraries.isEmpty,
                  scope.characterizationBindings.count == scope.cornerIDs.count else {
                throw .invalidInput("Incomplete functional operating process scope")
            }
        }
        for index in request.operatingConditionPolicies.indices {
            let policy = request.operatingConditionPolicies[index]
            try LogicReloadComparison.reference(policy.library, request.library.reference, context: &context)
            guard policy.library == request.library.reference, !policy.cell.isEmpty, policy.cornerID != "" else {
                throw .invalidInput("Foreign source-cell policy or invalid source-only/timing scope")
            }
            if let scope = request.operatingProcessScope {
                guard let selected = policy.cornerID else {
                    throw .invalidInput("Foreign source-cell policy or invalid source-only/timing scope")
                }
                var found = false
                for corner in scope.cornerIDs {
                    if try LogicReloadComparison.string(selected, corner, context: &context) { found = true; break }
                }
                guard found else { throw .invalidInput("Foreign source-cell policy or invalid source-only/timing scope") }
            } else if policy.cornerID != nil {
                throw .invalidInput("Foreign source-cell policy or invalid source-only/timing scope")
            }
            for priorIndex in 0..<index {
                let prior = request.operatingConditionPolicies[priorIndex]
                let cellEqual = try LogicReloadComparison.string(prior.cell, policy.cell, context: &context)
                var cornerEqual = prior.cornerID == nil && policy.cornerID == nil
                if let lhs = prior.cornerID, let rhs = policy.cornerID {
                    cornerEqual = try LogicReloadComparison.string(lhs, rhs, context: &context)
                }
                guard !cellEqual || !cornerEqual else { throw .invalidInput("Duplicate source-cell operating policy") }
            }
        }
        try metric(request.constraints.maximumArea, context: &context)
        try metric(request.constraints.maximumPower, context: &context)
        if let timing = request.constraints.timing {
            if let scope = request.operatingProcessScope { try scopeWork(scope, context: &context) }
            try scopeWork(timing.operatingProcessScope, context: &context)
            guard request.operatingProcessScope == timing.operatingProcessScope else {
                throw .invalidInput("Requested timing differs from functional operating process scope")
            }
            guard !timing.cornerIDs.isEmpty, !timing.modeIDs.isEmpty, timing.maximumPaths > 0,
                  timing.characterizationBindings.count == timing.cornerIDs.count,
                  !timing.libraries.isEmpty else {
                throw .invalidInput("Timing requires exact mapping library and observed corner conditions")
            }
            for library in timing.libraries {
                try LogicReloadComparison.reference(library.artifact.reference, request.library.reference, context: &context)
                guard library.artifact.reference == request.library.reference else {
                    throw .invalidInput("Timing requires exact mapping library and observed corner conditions")
                }
            }
            if let value = timing.minimumSetupSlack, !value.isFinite { throw .invalidInput("Slack limits must be finite") }
            if let value = timing.minimumHoldSlack, !value.isFinite { throw .invalidInput("Slack limits must be finite") }
        }
        try context.checkpoint()
    }

    private static func scopeWork(_ scope: LogicOperatingProcessScope,
                                  context: inout LogicKernelContext) throws(LogicKernelError) {
        try LogicReloadComparison.charge(UInt64(scope.processID.utf8.count), UInt64(scope.pdkVersion.utf8.count), context: &context)
        for corner in scope.cornerIDs {
            try LogicReloadComparison.charge(UInt64(corner.utf8.count), 1, context: &context)
        }
        for library in scope.libraries {
            try LogicReloadComparison.reference(library.artifact.reference, library.artifact.reference, context: &context)
            for corner in library.cornerIDs {
                try LogicReloadComparison.charge(UInt64(corner.utf8.count), 1, context: &context)
            }
        }
        for binding in scope.characterizationBindings {
            try LogicReloadComparison.charge(UInt64(binding.cornerID.utf8.count), UInt64(binding.conditionName.utf8.count), context: &context)
        }
    }

    private static func metric(_ value: Double?, context: inout LogicKernelContext) throws(LogicKernelError) {
        try context.charge(.workUnits)
        if let value, !value.isFinite || value < 0 { throw .invalidInput("Metric limits must be finite and nonnegative") }
    }
}
