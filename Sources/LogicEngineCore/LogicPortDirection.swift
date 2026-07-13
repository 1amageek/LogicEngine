import Foundation

public enum LogicPortDirection: String, Sendable, Hashable, Codable {
    case input
    case output
    case inoutPort = "inout"
}
