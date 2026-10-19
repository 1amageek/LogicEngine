import LogicEngineCore

public struct LogicSimulationVerificationRequest: Sendable, Hashable, Codable {
    public let acceptance: LogicArtifactBinding
    public let expectedRequest: LogicSimulationRequest
    public let limits: LogicRuntimeLimits
    public init(acceptance: LogicArtifactBinding, expectedRequest: LogicSimulationRequest, limits: LogicRuntimeLimits) {
        self.acceptance = acceptance; self.expectedRequest = expectedRequest; self.limits = limits
    }
}
