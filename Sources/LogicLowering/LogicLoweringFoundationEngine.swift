import CircuiteFoundation

/// Foundation-native lowering protocol used by standalone clients and flows.
public protocol LogicLoweringFoundationEngine: Engine
where Request == LogicLoweringFoundationRequest,
      Output == LogicLoweringFoundationResult {}
