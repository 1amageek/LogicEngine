import Foundation
import XcircuitePackage

public struct LogicBoundedTemporalEquivalencePayload: Sendable, Hashable, Codable {
    public var proofStatus: LogicBoundedTemporalEquivalenceStatus
    public var comparedSampleCount: Int
    public var mismatchCount: Int
    public var outputSignals: [String]
    public var referenceSimulationReport: XcircuiteFileReference?
    public var implementationSimulationReport: XcircuiteFileReference?
    public var equivalenceReport: XcircuiteFileReference?
    public var counterexample: XcircuiteFileReference?

    public init(
        proofStatus: LogicBoundedTemporalEquivalenceStatus,
        comparedSampleCount: Int,
        mismatchCount: Int,
        outputSignals: [String],
        referenceSimulationReport: XcircuiteFileReference? = nil,
        implementationSimulationReport: XcircuiteFileReference? = nil,
        equivalenceReport: XcircuiteFileReference? = nil,
        counterexample: XcircuiteFileReference? = nil
    ) {
        self.proofStatus = proofStatus
        self.comparedSampleCount = comparedSampleCount
        self.mismatchCount = mismatchCount
        self.outputSignals = outputSignals
        self.referenceSimulationReport = referenceSimulationReport
        self.implementationSimulationReport = implementationSimulationReport
        self.equivalenceReport = equivalenceReport
        self.counterexample = counterexample
    }
}
