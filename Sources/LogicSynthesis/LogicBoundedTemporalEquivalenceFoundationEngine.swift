import CircuiteFoundation

/// Foundation-native bounded temporal equivalence protocol.
public protocol LogicBoundedTemporalEquivalenceFoundationEngine: Engine
where Request == LogicBoundedTemporalEquivalenceFoundationRequest,
      Output == LogicBoundedTemporalEquivalenceFoundationResult {}
