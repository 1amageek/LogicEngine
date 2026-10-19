import Dispatch
import LogicKernelCore

internal struct LogicRuntimeControl: LogicRunControlling {
    let start: UInt64
    let timeout: UInt64
    init(timeout: UInt64) { start = DispatchTime.now().uptimeNanoseconds; self.timeout = timeout }
    func checkpoint() throws(LogicKernelError) {
        if Task.isCancelled { throw .cancelled }
        if DispatchTime.now().uptimeNanoseconds - start >= timeout { throw .deadlineExceeded }
    }
}
