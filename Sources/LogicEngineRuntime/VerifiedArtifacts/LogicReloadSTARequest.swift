import CircuiteFoundation
import LogicKernelCore
import STAEngine
import TimingCore

/// Offers the original STARequest constructor's visible derived payloads.
internal enum LogicReloadSTARequest {
    static func make(request: LogicSynthesisRequest, design: TimingArtifactBinding,
        constraints: LogicSynthesisTimingConstraints, supplies: [STAOperatingSupplyAssumption],
        resources: any LibertySourceResourceAccounting) throws
        -> (value: STARequest, retention: LibertySourceStorageReservation) {
        var bytes: UInt64 = 0
        func add(_ value: UInt64) throws {
            let next = bytes.addingReportingOverflow(value)
            guard !next.overflow else { throw LibertySourceError.arithmeticOverflow }
            bytes = next.partialValue
        }
        func array<T>(_ type: T.Type, count: UInt64) throws {
            let value = count.multipliedReportingOverflow(by: UInt64(MemoryLayout<T>.stride))
            guard !value.overflow else { throw LibertySourceError.arithmeticOverflow }
            try add(value.partialValue)
        }
        func table<Key>(_ type: Key.Type, count: UInt64) throws {
            let times = count.multipliedReportingOverflow(by: 4)
            guard !times.overflow else { throw LibertySourceError.arithmeticOverflow }
            let minimum = times.partialValue / 3 + 1
            var buckets: UInt64 = 1
            while buckets < minimum {
                try resources.check(); try resources.chargeWork(1)
                let next = buckets.multipliedReportingOverflow(by: 2)
                guard !next.overflow else { throw LibertySourceError.arithmeticOverflow }
                buckets = next.partialValue
            }
            let payload = buckets.multipliedReportingOverflow(by: UInt64(MemoryLayout<Key>.stride))
            let bits = (buckets / UInt64(UInt.bitWidth) + 1).multipliedReportingOverflow(by: UInt64(MemoryLayout<UInt>.stride))
            let total = payload.partialValue.addingReportingOverflow(bits.partialValue)
            let oldNew = total.partialValue.multipliedReportingOverflow(by: 2)
            guard !payload.overflow, !bits.overflow, !total.overflow, !oldNew.overflow else { throw LibertySourceError.arithmeticOverflow }
            try add(oldNew.partialValue)
        }
        func text(_ value: String) throws {
            let count = UInt64(value.utf8.count)
            try resources.check(); try resources.chargeWork(count)
            // trimming can materialize a String no larger than the original UTF-8.
            try add(count)
        }
        try text(request.runID); try text(request.top)
        try text(constraints.processID); try text(constraints.pdkVersion)
        for value in constraints.modeIDs { try text(value) }
        for value in constraints.cornerIDs { try text(value) }
        try table(String.self, count: UInt64(constraints.modeIDs.count))
        try table(String.self, count: UInt64(constraints.cornerIDs.count))
        let count = UInt64(supplies.count)
        try array([String].self, count: count)
        let inner = count.multipliedReportingOverflow(by: 3)
        guard !inner.overflow else { throw LibertySourceError.arithmeticOverflow }
        try array(String.self, count: inner.partialValue)
        try table([String].self, count: count)
        for supply in supplies {
            try resources.check()
            for corner in constraints.cornerIDs {
                let width = UInt64(corner.utf8.count).addingReportingOverflow(UInt64(supply.cornerID.utf8.count))
                guard !width.overflow else { throw LibertySourceError.arithmeticOverflow }
                try resources.chargeWork(width.partialValue + 1)
            }
        }
        let libraryCount = UInt64(constraints.libraries.count)
        let total = libraryCount.addingReportingOverflow(3)
        guard !total.overflow else { throw LibertySourceError.arithmeticOverflow }
        // Original chained bindings construction: literals, mapped libraries,
        // concatenated old/new arrays, then the retained reference projection.
        try array(TimingArtifactBinding.self, count: 1)
        try array(TimingArtifactBinding.self, count: libraryCount)
        try array(TimingArtifactBinding.self, count: libraryCount + 1)
        try array(TimingArtifactBinding.self, count: 2)
        try array(TimingArtifactBinding.self, count: total.partialValue)
        try array(TimingArtifactBinding.self, count: total.partialValue)
        try array(ArtifactReference.self, count: total.partialValue)
        let reservation = try resources.reserveStorage(kind: .temporaryBytes, byteCount: bytes)
        try resources.check()
        let value = try STARequest(runID: request.runID, design: design, topDesignName: request.top,
            libraries: constraints.libraries, constraints: constraints.constraints,
            requestedModeIDs: constraints.modeIDs, requestedCornerIDs: constraints.cornerIDs,
            pdkManifest: constraints.pdkManifest, processID: constraints.processID, pdkVersion: constraints.pdkVersion,
            maxPaths: constraints.maximumPaths, characterizationPolicy: .requireObservedConditions,
            characterizationBindings: constraints.characterizationBindings, operatingSupplyAssumptions: supplies)
        try resources.check()
        return (value, reservation)
    }
}
