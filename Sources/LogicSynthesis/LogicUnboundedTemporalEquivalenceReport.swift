import Foundation
import LogicEngineCore

public struct LogicUnboundedTemporalEquivalenceReport: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let runID: String
    public let proofScope: String
    public let requestDigest: String
    public let referenceDesignDigest: String
    public let implementationDesignDigest: String
    public let valueDomain: LogicUnboundedTemporalEquivalenceDomain
    public let outputSignals: [String]
    public let stateSignals: [String]
    public let inputSignals: [String]
    public let stateSpaceLimit: Int
    public let transitionLimit: Int
    public let exploredStateCount: Int
    public let exploredTransitionCount: Int
    public let solverID: String
    public let solverVersion: String
    public let status: LogicUnboundedTemporalEquivalenceStatus
    public let differences: [LogicUnboundedTemporalEquivalenceDifference]

    public init(
        runID: String,
        requestDigest: String,
        referenceDesignDigest: String,
        implementationDesignDigest: String,
        valueDomain: LogicUnboundedTemporalEquivalenceDomain,
        outputSignals: [String],
        stateSignals: [String],
        inputSignals: [String],
        stateSpaceLimit: Int,
        transitionLimit: Int,
        exploredStateCount: Int,
        exploredTransitionCount: Int,
        solverID: String,
        solverVersion: String,
        status: LogicUnboundedTemporalEquivalenceStatus,
        differences: [LogicUnboundedTemporalEquivalenceDifference] = [],
        proofScope: String = "native-exhaustive-finite-state-v1"
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.proofScope = proofScope
        self.requestDigest = requestDigest
        self.referenceDesignDigest = referenceDesignDigest
        self.implementationDesignDigest = implementationDesignDigest
        self.valueDomain = valueDomain
        self.outputSignals = outputSignals
        self.stateSignals = stateSignals
        self.inputSignals = inputSignals
        self.stateSpaceLimit = stateSpaceLimit
        self.transitionLimit = transitionLimit
        self.exploredStateCount = exploredStateCount
        self.exploredTransitionCount = exploredTransitionCount
        self.solverID = solverID
        self.solverVersion = solverVersion
        self.status = status
        self.differences = differences
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion,
              !runID.isEmpty,
              !proofScope.isEmpty,
              !requestDigest.isEmpty,
              !referenceDesignDigest.isEmpty,
              !implementationDesignDigest.isEmpty,
              !solverID.isEmpty,
              !solverVersion.isEmpty else {
            throw LogicExecutionError.invalidArtifact(
                "unbounded temporal equivalence report identity is incomplete"
            )
        }
        guard stateSpaceLimit > 0,
              transitionLimit > 0,
              exploredStateCount >= 0,
              exploredTransitionCount >= 0,
              exploredStateCount <= stateSpaceLimit,
              exploredTransitionCount <= transitionLimit else {
            throw LogicExecutionError.invalidArtifact(
                "unbounded temporal equivalence report counts exceed declared limits"
            )
        }
        guard !outputSignals.isEmpty,
              Set(outputSignals).count == outputSignals.count,
              outputSignals.allSatisfy({ !$0.isEmpty }) else {
            throw LogicExecutionError.invalidArtifact(
                "unbounded temporal equivalence report output signals are invalid"
            )
        }
        switch status {
        case .proved:
            guard differences.isEmpty, exploredTransitionCount > 0 else {
                throw LogicExecutionError.invalidArtifact(
                    "proved unbounded temporal equivalence report is incomplete"
                )
            }
        case .counterexample:
            guard !differences.isEmpty else {
                throw LogicExecutionError.invalidArtifact(
                    "counterexample report has no differences"
                )
            }
        case .blocked, .timeout:
            break
        }
    }
}
