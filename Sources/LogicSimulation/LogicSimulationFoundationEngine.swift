import CircuiteFoundation

/// Foundation-native simulation protocol used directly by Xcircuite and
/// standalone agents.
public protocol LogicSimulationFoundationEngine: Engine
where Request == LogicSimulationFoundationRequest,
      Output == LogicSimulationFoundationResult {}
