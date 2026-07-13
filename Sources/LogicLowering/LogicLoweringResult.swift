import Foundation
import LogicEngineCore
import XcircuitePackage

public struct LogicLoweringResult: Sendable, Hashable, Codable {
    public var status: XcircuiteEngineExecutionStatus
    public var document: LogicDesignDocument?
    public var diagnostics: [XcircuiteEngineDiagnostic]

    public init(
        status: XcircuiteEngineExecutionStatus,
        document: LogicDesignDocument? = nil,
        diagnostics: [XcircuiteEngineDiagnostic] = []
    ) {
        self.status = status
        self.document = document
        self.diagnostics = diagnostics
    }
}
