import Foundation
import CircuiteFoundation

public protocol LogicBoundedTemporalEquivalenceExecuting: Engine
where Request == LogicBoundedTemporalEquivalenceRequest,
      Output == LogicBoundedTemporalEquivalenceResult {}
