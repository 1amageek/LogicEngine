import Foundation
import LogicEngineCore

public struct LogicUnboundedTemporalEquivalenceDifference: Sendable, Hashable, Codable {
    public let state: [String: LogicVector]
    public let inputs: [String: LogicVector]
    public let previousClock: LogicValue?
    public let currentClock: LogicValue?
    public let referenceOutputs: [String: LogicVector]
    public let implementationOutputs: [String: LogicVector]
    public let referenceNextState: [String: LogicVector]
    public let implementationNextState: [String: LogicVector]

    public init(
        state: [String: LogicVector],
        inputs: [String: LogicVector],
        previousClock: LogicValue?,
        currentClock: LogicValue?,
        referenceOutputs: [String: LogicVector],
        implementationOutputs: [String: LogicVector],
        referenceNextState: [String: LogicVector] = [:],
        implementationNextState: [String: LogicVector] = [:]
    ) {
        self.state = state
        self.inputs = inputs
        self.previousClock = previousClock
        self.currentClock = currentClock
        self.referenceOutputs = referenceOutputs
        self.implementationOutputs = implementationOutputs
        self.referenceNextState = referenceNextState
        self.implementationNextState = implementationNextState
    }
}
