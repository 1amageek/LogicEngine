import CircuiteFoundation

/// Foundation-native simulation protocol used by standalone clients and flows.
public protocol LogicSimulationFoundationEngine: Engine
where Request == LogicSimulationFoundationRequest,
      Output == LogicSimulationFoundationResult {}
