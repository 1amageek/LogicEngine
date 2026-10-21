import LogicEngineCore
import LogicKernelCore

extension NativeLogicSynthesisEngine: LogicSynthesisArtifactControlledLoading {
    public nonisolated(nonsending) func load(_ receipt: LogicArtifactBinding, limits: LogicRuntimeLimits,
        context: inout LogicKernelContext, resources: LogicReloadResources) async throws
        -> (value: LogicVerifiedSynthesis, retention: LogicReloadRetention) {
        try context.requireAccounting(expected: resources)
        guard limits.maximumInputBytes > 0, limits.maximumOutputBytes > 0,
              limits.timeoutNanoseconds > 0, limits.maximumTokens > 0,
              limits.maximumTableEntries > 0, limits.maximumNesting > 0 else {
            throw LogicKernelError.invalidInput("Host byte/time/syntax capacities must be positive")
        }
        try context.checkpoint()
        try resources.checkCaller()
        // Offer the inspectable host failure frame before any fallible source phase.
        // Arbitrary caller causes retain their caller-owned payloads; only this frame
        // and each lower owner's explicit diagnostic payload belong to this adapter.
        let failureFrame: LogicKernelRetention
        do {
            failureFrame = try LogicReloadKernelPhase.run(context: &context, resources: resources) { inner in
                _ = try inner.reserveStorage(byteCount: UInt64(MemoryLayout<LogicControlledReloadFailure>.stride))
                return true
            }.retention
        } catch {
            // This initial scope can only emit scalar/static kernel failures. No
            // decoded/source diagnostic payload exists before its admission.
            if let primary = resources.externalFailure { throw primary }
            throw error
        }
        var loaded: LogicReloadState?
        do {
            guard let reader = artifactStore as? any LogicArtifactControlledReading else {
                throw LogicKernelError.unsupported("Artifact store does not support controlled reads")
            }
            let state = try await LogicReloadCapture.capture(receipt, store: reader, limits: limits,
                context: &context, resources: resources)
            loaded = state
            var io = LogicRuntimeIO(store: artifactStore, limits: limits, control: context.checkpointControl,
                controlled: state)
            // Legacy load consumed the receipt and request before reload read the
            // request again. Keep that cumulative logical-read policy, without
            // pretending the immutable snapshot was physically read/hashed twice.
            _ = try io.read(receipt, context: &context)
            _ = try io.read(state.receipt.value.request, context: &context)
            let value = try await Self.reload(state.receipt.value, expectedRequest: state.request.value,
                io: &io, context: &context)
            try context.checkpoint()
            try resources.checkCaller()
            return (value, state.retention())
        } catch {
            if let primary = resources.externalFailure {
                throw LogicControlledReloadFailure(primary: primary, secondary: error, retention: failureFrame, documentRetention: loaded)
            }
            throw LogicControlledReloadFailure(primary: error, retention: failureFrame, documentRetention: loaded)
        }
    }
}
