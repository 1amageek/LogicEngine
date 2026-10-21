import LogicKernelCore

/// Keeps original causes and the whole anchored lower failure inspectable.
public struct LogicControlledReloadFailure: Error, Sendable {
    public let primary: any Error
    public let secondary: (any Error)?
    private let retention: LogicKernelRetention?
    private let documentRetention: (any Sendable)?

    internal init(primary: any Error, secondary: (any Error)? = nil,
                  retention: LogicKernelRetention? = nil, documentRetention: (any Sendable)? = nil) {
        self.primary = primary; self.secondary = secondary; self.retention = retention; self.documentRetention = documentRetention
    }
}
