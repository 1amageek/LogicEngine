import Foundation
import XcircuitePackage

public struct LogicQualificationObservation: Sendable, Hashable, Codable {
    public var status: XcircuiteEngineExecutionStatus
    public var diagnosticCodes: [String]
    public var artifactIDs: [String]

    public init(
        status: XcircuiteEngineExecutionStatus,
        diagnosticCodes: [String] = [],
        artifactIDs: [String] = []
    ) {
        self.status = status
        self.diagnosticCodes = Array(Set(diagnosticCodes)).sorted()
        self.artifactIDs = Array(Set(artifactIDs)).sorted()
    }
}
