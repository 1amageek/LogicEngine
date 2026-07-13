import Foundation

public enum LogicUnboundedTemporalEquivalenceStatus: String, Sendable, Hashable, Codable {
    case proved
    case counterexample
    case blocked
    case timeout
}
