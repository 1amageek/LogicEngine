import LogicIR

public struct LogicSimulationState: ~Copyable {
    internal let owner: LogicSimulationModel.Storage
    internal let rtl: RTLEventWorkspace?
    internal var values: [LogicBit]
    internal var states: [LogicBit]
    internal var pending: [LogicBit]
    internal var previousControls: [LogicBit]
    internal var functions: [LogicBit]
    internal var valid = true
    internal var time: UInt64 = 0
    internal init(owner: LogicSimulationModel.Storage, values: consuming [LogicBit], states: consuming [LogicBit],
                  pending: consuming [LogicBit], previousControls: consuming [LogicBit], functions: consuming [LogicBit]) {
        self.rtl = nil
        self.owner = owner; self.values = values; self.states = states; self.pending = pending
        self.previousControls = previousControls; self.functions = functions
    }
    internal init(owner: LogicSimulationModel.Storage, rtl: RTLEventWorkspace) {
        self.owner = owner; self.rtl = rtl
        values = []; states = []; pending = []; previousControls = []; functions = []
    }
}
