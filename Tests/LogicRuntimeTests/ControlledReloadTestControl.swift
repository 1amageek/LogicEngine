import LogicKernelCore
import Synchronization

final class ControlledReloadTestControl: LogicRunControlling {
    private let state = Mutex(false)
    var isCancelled: Bool { state.withLock { $0 } }
    func cancel() { state.withLock { $0 = true } }
    func checkpoint() throws(LogicKernelError) {
        if isCancelled { throw .cancelled }
    }
}
