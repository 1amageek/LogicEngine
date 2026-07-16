import CircuiteFoundation
import LogicEngineCore
import LogicIR

/// In-memory lowering outcome before execution artifacts and provenance exist.
public struct LogicLoweringOutcome: Sendable, Hashable {
    public let status: LogicExecutionStatus
    public let document: LogicDesignDocument?
    public let diagnostics: [DesignDiagnostic]

    public init(
        status: LogicExecutionStatus,
        document: LogicDesignDocument? = nil,
        diagnostics: [DesignDiagnostic] = []
    ) {
        self.status = status
        self.document = document
        self.diagnostics = diagnostics
    }
}
