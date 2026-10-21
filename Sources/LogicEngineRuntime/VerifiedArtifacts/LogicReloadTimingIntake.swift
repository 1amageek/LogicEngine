import Foundation
import LogicKernelCore
import STAEngine
import TimingCore

internal enum LogicReloadTimingIntake {
    static func decodeSaved(_ data: Data, limits: LogicRuntimeLimits,
        context: inout LogicKernelContext, resources: LogicReloadResources) throws
        -> TimingTransformValue<STAExecutionResult> {
        let phase = try LogicReloadPhase.make(context: &context, resources: resources)
        let result: TimingTransformValue<STAExecutionResult>
        do {
            let source = try LogicReloadLibertyResources.make(phase: phase)
            let configuration = try executionResources(reader: InMemoryTimingArtifactReader(artifacts: [:]),
                source: source, limits: limits, work: context.limits[.workUnits] - context.usage[.workUnits])
            result = try STAExecutionResult.decodeBounded(data, resources: configuration)
        }
        catch {
            do { try phase.importOnce(into: &context) }
            catch let cleanup { throw LogicControlledReloadFailure(primary: resources.resolved(error), secondary: cleanup) }
            throw resources.resolved(error)
        }
        try phase.importOnce(into: &context)
        try resources.checkCaller()
        return result
    }

    static func executionResources(reader: any TimingArtifactReading,
        source: any LibertySourceResourceAccounting, limits: LogicRuntimeLimits,
        work: UInt64) throws -> STAExecutionResources {
        guard work > 0 else { throw LogicKernelError.resourceLimit(resource: .workUnits, limit: 0, requested: nil) }
        let entries = limits.maximumTableEntries
        let canonical = try STAExecutionLimits()
        return try .init(reader: reader,
            sourceLimits: LibertySourceParseLimits(maximumNestingDepth: limits.maximumNesting),
            sourceResources: source,
            limits: STAExecutionLimits(maximumInputBytes: limits.maximumInputBytes,
                maximumScenarios: entries, maximumDesignElements: entries, maximumPaths: entries,
                maximumPathStates: canonical.maximumPathStates,
                maximumPathWorkUnits: canonical.maximumPathWorkUnits),
            requiresStrictTransformAccounting: true)
    }
}
