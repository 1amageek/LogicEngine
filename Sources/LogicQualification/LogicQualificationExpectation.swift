import Foundation
import XcircuitePackage

public struct LogicQualificationExpectation: Sendable, Hashable, Codable {
    public var expectedStatus: XcircuiteEngineExecutionStatus
    public var requiredDiagnosticCodes: [String]
    public var forbiddenDiagnosticCodes: [String]

    public init(
        expectedStatus: XcircuiteEngineExecutionStatus,
        requiredDiagnosticCodes: [String] = [],
        forbiddenDiagnosticCodes: [String] = []
    ) {
        self.expectedStatus = expectedStatus
        self.requiredDiagnosticCodes = Array(Set(requiredDiagnosticCodes)).sorted()
        self.forbiddenDiagnosticCodes = Array(Set(forbiddenDiagnosticCodes)).sorted()
    }
}
