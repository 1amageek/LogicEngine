import Foundation

public struct LogicWaveformSample: Sendable, Hashable, Codable {
    public var time: Int64
    public var values: [String: LogicVector]

    public init(time: Int64, values: [String: LogicVector]) {
        self.time = time
        self.values = values
    }
}
