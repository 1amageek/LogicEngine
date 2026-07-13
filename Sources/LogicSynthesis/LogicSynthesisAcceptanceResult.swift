import Foundation
import XcircuitePackage

public struct LogicSynthesisAcceptanceResult: Sendable, Hashable, Codable {
    public let state: LogicSynthesisAcceptanceState
    public let diagnostics: [XcircuiteEngineDiagnostic]

    public init(
        state: LogicSynthesisAcceptanceState,
        diagnostics: [XcircuiteEngineDiagnostic] = []
    ) {
        self.state = state
        self.diagnostics = diagnostics
    }
}
