import Foundation
import CircuiteFoundation
import LogicIR
import PowerIntent
import TimingCore
import PDKCore

public protocol LogicSynthesisExecuting: Engine
where Request == LogicSynthesisRequest, Output == LogicSynthesisResult {}
