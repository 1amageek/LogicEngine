import Foundation

public struct LogicCell: Sendable, Hashable, Codable {
    public var name: String
    public var kind: LogicNodeKind
    public var inputCount: Int
    public var area: Double
    public var power: Double
    public var driveStrength: Int

    public init(
        name: String,
        kind: LogicNodeKind,
        inputCount: Int,
        area: Double,
        power: Double,
        driveStrength: Int = 0
    ) {
        self.name = name
        self.kind = kind
        self.inputCount = inputCount
        self.area = area
        self.power = power
        self.driveStrength = driveStrength
    }
}
