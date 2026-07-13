import Foundation
import LogicEngineCore

public struct LogicBoundedTemporalEquivalenceDifference: Sendable, Hashable, Codable {
    public var time: Int64
    public var signal: String
    public var referenceValue: LogicVector?
    public var implementationValue: LogicVector?

    public init(
        time: Int64,
        signal: String,
        referenceValue: LogicVector?,
        implementationValue: LogicVector?
    ) {
        self.time = time
        self.signal = signal
        self.referenceValue = referenceValue
        self.implementationValue = implementationValue
    }
}
