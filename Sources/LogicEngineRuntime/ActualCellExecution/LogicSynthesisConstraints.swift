import STAEngine
import TimingCore

public struct LogicSynthesisConstraints: Sendable, Hashable, Codable {
    public let maximumArea: Double?
    public let maximumPower: Double?
    public let timing: LogicSynthesisTimingConstraints?
    public init(maximumArea: Double? = nil, maximumPower: Double? = nil,
                timing: LogicSynthesisTimingConstraints? = nil) {
        self.maximumArea = maximumArea; self.maximumPower = maximumPower; self.timing = timing
    }
}
