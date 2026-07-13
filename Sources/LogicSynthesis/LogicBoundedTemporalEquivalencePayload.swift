import Foundation
import CircuiteFoundation
import CircuiteFoundation

public struct LogicBoundedTemporalEquivalencePayload: Sendable, Hashable, Codable {
    public var proofStatus: LogicBoundedTemporalEquivalenceStatus
    public var comparedSampleCount: Int
    public var mismatchCount: Int
    public var outputSignals: [String]
    public var referenceSimulationReport: ArtifactReference?
    public var implementationSimulationReport: ArtifactReference?
    public var equivalenceReport: ArtifactReference?
    public var counterexample: ArtifactReference?

    public init(
        proofStatus: LogicBoundedTemporalEquivalenceStatus,
        comparedSampleCount: Int,
        mismatchCount: Int,
        outputSignals: [String],
        referenceSimulationReport: ArtifactReference? = nil,
        implementationSimulationReport: ArtifactReference? = nil,
        equivalenceReport: ArtifactReference? = nil,
        counterexample: ArtifactReference? = nil
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
