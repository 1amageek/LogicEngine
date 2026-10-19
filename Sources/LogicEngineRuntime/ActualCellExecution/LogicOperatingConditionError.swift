import LogicKernelCore
import TimingCore

public enum LogicOperatingConditionError: Error, Sendable {
    case invalidInput(String)
    case source(LibertyNormalPowerError)
    case kernel(LogicKernelError)
}
