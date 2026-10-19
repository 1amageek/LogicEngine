import CircuiteFoundation

public protocol LogicSynthesisExecuting: Engine where Request == LogicSynthesisRequest, Output == LogicSynthesisResult {}
