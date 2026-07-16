import CircuiteFoundation
import Foundation
import LogicEngineCore

public struct LogicUnboundedTemporalEquivalencePayload: Sendable, Hashable, Codable {
    public let proofStatus: LogicUnboundedTemporalEquivalenceStatus
    public let exploredStateCount: Int
    public let exploredTransitionCount: Int
    public let outputSignals: [String]
    public let stateSignals: [String]
    public let inputSignals: [String]
    public let equivalenceReport: ArtifactReference?
    public let proofCertificate: ArtifactReference?
    public let counterexample: ArtifactReference?

    public init(
        proofStatus: LogicUnboundedTemporalEquivalenceStatus,
        exploredStateCount: Int = 0,
        exploredTransitionCount: Int = 0,
        outputSignals: [String] = [],
        stateSignals: [String] = [],
        inputSignals: [String] = [],
        equivalenceReport: ArtifactReference? = nil,
        proofCertificate: ArtifactReference? = nil,
        counterexample: ArtifactReference? = nil
    ) {
        self.proofStatus = proofStatus
        self.exploredStateCount = exploredStateCount
        self.exploredTransitionCount = exploredTransitionCount
        self.outputSignals = outputSignals
        self.stateSignals = stateSignals
        self.inputSignals = inputSignals
        self.equivalenceReport = equivalenceReport
        self.proofCertificate = proofCertificate
        self.counterexample = counterexample
    }
}
