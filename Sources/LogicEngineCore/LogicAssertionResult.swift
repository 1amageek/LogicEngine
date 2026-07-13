import Foundation

public struct LogicAssertionResult: Sendable, Hashable, Codable {
    public var assertionID: String
    public var passed: Bool
    public var observed: LogicVector?
    public var expected: LogicVector
    public var time: Int64

    public init(
        assertionID: String,
        passed: Bool,
        observed: LogicVector?,
        expected: LogicVector,
        time: Int64
    ) {
        self.assertionID = assertionID
        self.passed = passed
        self.observed = observed
        self.expected = expected
        self.time = time
    }
}
