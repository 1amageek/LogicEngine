import LogicKernelCore

internal struct LogicReloadRetainedParts: Sendable {
    var compilation: LogicKernelRetention?
    var original: LogicKernelRetention?
    var identities: LogicKernelRetention?
    var mapped: LogicKernelRetention?
    var operating: LogicKernelRetention?
    var certificate: LogicKernelRetention?
    var proof: LogicKernelRetention?
}
