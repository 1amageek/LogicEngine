import Foundation
import XcircuitePackage
import LogicIR
import PowerIntent
import TimingCore
import PDKCore

public protocol LogicSynthesisExecuting: Sendable {
    func execute(
        _ request: LogicSynthesisRequest
    ) async throws -> XcircuiteEngineResultEnvelope<LogicSynthesisPayload>
}
