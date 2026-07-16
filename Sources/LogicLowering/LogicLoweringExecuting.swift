import Foundation
import CircuiteFoundation

public protocol LogicLoweringExecuting: Engine
where Request == LogicLoweringRequest, Output == LogicLoweringResult {}
