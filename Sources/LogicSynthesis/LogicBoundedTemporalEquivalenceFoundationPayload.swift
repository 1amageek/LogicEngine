import CircuiteFoundation
import Foundation

/// Foundation-native bounded-equivalence metrics and proof artifacts.
public struct LogicBoundedTemporalEquivalenceFoundationPayload: Sendable, Hashable, Codable {
    public let proofStatus: LogicBoundedTemporalEquivalenceStatus
    public let comparedSampleCount: Int
    public let mismatchCount: Int
    public let outputSignals: [String]
    public let referenceSimulationReport: ArtifactReference?
    public let implementationSimulationReport: ArtifactReference?
    public let equivalenceReport: ArtifactReference?
    public let counterexample: ArtifactReference?

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
