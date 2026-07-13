import Foundation
import CircuiteFoundation

public struct LogicSynthesisAcceptanceResult: Sendable, Hashable, Codable {
    public let state: LogicSynthesisAcceptanceState
    public let diagnostics: [DesignDiagnostic]

    public init(
        state: LogicSynthesisAcceptanceState,
        diagnostics: [DesignDiagnostic] = []
    ) {
        self.state = state
        self.diagnostics = diagnostics
    }
}
