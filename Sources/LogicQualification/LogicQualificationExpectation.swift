import Foundation
import LogicEngineCore

public struct LogicQualificationExpectation: Sendable, Hashable, Codable {
    public var expectedStatus: LogicExecutionStatus
    public var requiredDiagnosticCodes: [String]
    public var forbiddenDiagnosticCodes: [String]

    public init(
        expectedStatus: LogicExecutionStatus,
        requiredDiagnosticCodes: [String] = [],
        forbiddenDiagnosticCodes: [String] = []
    ) {
        self.expectedStatus = expectedStatus
        self.requiredDiagnosticCodes = Array(Set(requiredDiagnosticCodes)).sorted()
        self.forbiddenDiagnosticCodes = Array(Set(forbiddenDiagnosticCodes)).sorted()
    }
}
