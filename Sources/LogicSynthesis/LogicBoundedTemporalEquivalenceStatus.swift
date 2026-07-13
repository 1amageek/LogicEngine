import Foundation

public enum LogicBoundedTemporalEquivalenceStatus: String, Sendable, Hashable, Codable {
    case proved
    case counterexample
    case blocked
}
