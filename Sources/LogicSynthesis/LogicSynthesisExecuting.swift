import Foundation
import LogicIR
import PowerIntent
import TimingCore
import PDKCore

public protocol LogicSynthesisExecuting: Sendable {
    func execute(
        _ request: LogicSynthesisRequest
    ) async throws -> LogicSynthesisResult
}
