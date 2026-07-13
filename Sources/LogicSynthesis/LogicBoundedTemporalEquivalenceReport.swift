import Foundation
import LogicEngineCore

public struct LogicBoundedTemporalEquivalenceReport: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var proofScope: String
    public var requestDigest: String
    public var stimulusDigest: String
    public var referenceDesignDigest: String
    public var implementationDesignDigest: String
    public var outputSignals: [String]
    public var sampleLimit: Int
    public var comparedSampleCount: Int
    public var differences: [LogicBoundedTemporalEquivalenceDifference]
    public var status: LogicBoundedTemporalEquivalenceStatus

    public init(
        runID: String,
        requestDigest: String,
        stimulusDigest: String,
        referenceDesignDigest: String,
        implementationDesignDigest: String,
        outputSignals: [String],
        sampleLimit: Int,
        comparedSampleCount: Int,
        differences: [LogicBoundedTemporalEquivalenceDifference],
        status: LogicBoundedTemporalEquivalenceStatus,
        proofScope: String = "bounded-temporal-trace-v1"
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.proofScope = proofScope
        self.requestDigest = requestDigest
        self.stimulusDigest = stimulusDigest
        self.referenceDesignDigest = referenceDesignDigest
        self.implementationDesignDigest = implementationDesignDigest
        self.outputSignals = outputSignals
        self.sampleLimit = sampleLimit
        self.comparedSampleCount = comparedSampleCount
        self.differences = differences
        self.status = status
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicExecutionError.invalidArtifact(
                "unsupported bounded temporal equivalence report schema version \(schemaVersion)"
            )
        }
        guard !runID.isEmpty,
              !proofScope.isEmpty,
              !requestDigest.isEmpty,
              !stimulusDigest.isEmpty,
              !referenceDesignDigest.isEmpty,
              !implementationDesignDigest.isEmpty else {
            throw LogicExecutionError.invalidArtifact(
                "bounded temporal equivalence report identity is incomplete"
            )
        }
        guard sampleLimit > 0,
              comparedSampleCount >= 0,
              comparedSampleCount <= sampleLimit else {
            throw LogicExecutionError.invalidArtifact(
                "bounded temporal equivalence report sample count is outside its declared bound"
            )
        }
        guard !outputSignals.isEmpty,
              Set(outputSignals).count == outputSignals.count,
              outputSignals.allSatisfy({ !$0.isEmpty }) else {
            throw LogicExecutionError.invalidArtifact(
                "bounded temporal equivalence report output signals are invalid"
            )
        }
        switch status {
        case .proved:
            guard differences.isEmpty else {
                throw LogicExecutionError.invalidArtifact(
                    "proved bounded temporal equivalence report contains differences"
                )
            }
        case .counterexample:
            guard !differences.isEmpty else {
                throw LogicExecutionError.invalidArtifact(
                    "counterexample bounded temporal equivalence report has no differences"
                )
            }
        case .blocked:
            break
        }
    }
}
