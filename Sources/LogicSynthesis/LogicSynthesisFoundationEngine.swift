import CircuiteFoundation

/// Foundation-native synthesis protocol used by standalone clients and flows.
public protocol LogicSynthesisFoundationEngine: Engine
where Request == LogicSynthesisFoundationRequest,
      Output == LogicSynthesisFoundationResult {}
