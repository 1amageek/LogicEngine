import Foundation

public struct LogicPort: Sendable, Hashable, Codable {
    public var name: String
    public var direction: LogicPortDirection
    public var width: Int

    public init(name: String, direction: LogicPortDirection, width: Int = 1) {
        self.name = name
        self.direction = direction
        self.width = width
    }
}
