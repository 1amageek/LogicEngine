import Foundation

public struct LogicSignal: Sendable, Hashable, Codable {
    public var name: String
    public var width: Int
    public var isSigned: Bool
    public var initialValue: LogicVector?

    public init(name: String, width: Int = 1, isSigned: Bool = false, initialValue: LogicVector? = nil) {
        self.name = name
        self.width = width
        self.isSigned = isSigned
        self.initialValue = initialValue
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case width
        case isSigned
        case initialValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        width = try container.decode(Int.self, forKey: .width)
        isSigned = try container.decode(Bool.self, forKey: .isSigned)
        initialValue = try container.decodeIfPresent(LogicVector.self, forKey: .initialValue)
    }
}
