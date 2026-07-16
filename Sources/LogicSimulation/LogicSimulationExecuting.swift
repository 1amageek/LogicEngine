import Foundation
import LogicIR
import CircuiteFoundation

public protocol LogicSimulationExecuting: Engine
where Request == LogicSimulationRequest, Output == LogicSimulationResult {}
