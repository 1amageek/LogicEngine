import CircuiteFoundation

public protocol LogicEquivalenceExecuting: Engine where Request == LogicEquivalenceRequest, Output == LogicEquivalenceResult {}
