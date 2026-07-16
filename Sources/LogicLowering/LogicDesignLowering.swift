import Foundation
import LogicEngineCore
import LogicIR

public protocol LogicDesignLowering: Sendable {
    func lower(_ snapshot: LogicDesignSnapshot) -> LogicLoweringOutcome
}
