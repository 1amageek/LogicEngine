public struct LogicSimulationAssessment: Sendable, Hashable, Codable {
    public enum Status: String, Sendable, Hashable, Codable { case unassessed, passed, failed }
    public struct Violation: Sendable, Hashable, Codable {
        public enum Reason: String, Sendable, Hashable, Codable {
            case missingObservation, timeMismatch, missingOutput, valueMismatch
        }
        public let assertionID: String
        public let reason: Reason
        public let observationIndex: Int
        public let expectedTime: UInt64
        public let actualTime: UInt64?
        public let portIndex: Int
        public let expectedValue: String
        public let actualValue: String?
    }
    public enum Failure: Error, Sendable, Equatable {
        case unassessed
        case violations([Violation])
    }
    public let status: Status
    public let checkedAssertionCount: Int
    public let violations: [Violation]
    public func requirePassed() throws(Failure) {
        switch status {
        case .unassessed: throw .unassessed
        case .failed: throw .violations(violations)
        case .passed: return
        }
    }
    internal init(status: Status, checkedAssertionCount: Int, violations: [Violation]) {
        self.status = status; self.checkedAssertionCount = checkedAssertionCount; self.violations = violations
    }
}
