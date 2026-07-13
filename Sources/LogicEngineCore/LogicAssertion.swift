import Foundation

public struct LogicAssertion: Sendable, Hashable, Codable {
    public var id: String
    public var time: Int64
    public var signal: String
    public var expected: LogicVector

    public init(id: String, time: Int64, signal: String, expected: LogicVector) {
        self.id = id
        self.time = time
        self.signal = signal
        self.expected = expected
    }
}
