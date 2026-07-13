import Foundation

public enum LogicSynthesisAcceptanceState: String, Sendable, Hashable, Codable {
    case pendingEquivalence
    case accepted
    case rejected
}
