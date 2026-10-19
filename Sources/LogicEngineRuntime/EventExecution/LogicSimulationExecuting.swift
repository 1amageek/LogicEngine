import CircuiteFoundation

public protocol LogicSimulationExecuting: Engine where Request == LogicSimulationRequest, Output == LogicSimulationResult {}
