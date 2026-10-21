import LogicKernelCore

internal enum LogicReloadKernelPhase {
    static func run<Value: Sendable>(context: inout LogicKernelContext, resources: LogicReloadResources,
        _ body: (inout LogicKernelContext) throws -> Value) throws
        -> (value: Value, retention: LogicKernelRetention) {
        try context.requireAccounting(expected: resources)
        let scope = try context.beginRetentionScope()
        let value: Value
        let retention: LogicKernelRetention
        do {
            value = try body(&context)
            try resources.checkCaller()
            retention = try context.finishRetentionScope(scope)
        } catch {
            throw failure(error, scope: scope, context: &context, resources: resources)
        }
        try resources.checkCaller()
        return (value, retention)
    }
    /// Failure transfer is cancellation-independent and performs no new admission.
    /// A source-generated diagnostic may share backing with any admitted table.
    static func failure(_ error: any Error, scope: borrowing LogicKernelRetentionScope,
        context: inout LogicKernelContext, resources: LogicReloadResources) -> any Error {
        do {
            let retention = try context.retainFailureScope(scope)
            if let primary = resources.externalFailure {
                return LogicControlledReloadFailure(primary: primary, secondary: error, retention: retention)
            }
            return LogicControlledReloadFailure(primary: error, retention: retention)
        } catch let cleanup {
            return LogicControlledReloadFailure(primary: resources.resolved(error), secondary: cleanup)
        }
    }

}
