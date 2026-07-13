import CircuiteFoundation
import Foundation
import LogicEngineCore

/// Request for an exhaustive finite-state proof with no trace-length bound.
///
/// The proof is exact for the declared value domain when the complete finite
/// state/input relation fits within the declared limits. A result certificate
/// records those limits and the explored relation so callers can distinguish a
/// proof from a bounded trace experiment.
public struct LogicUnboundedTemporalEquivalenceFoundationRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = SchemaVersion.v1

    public let schemaVersion: SchemaVersion
    public let runID: String
    public let inputs: [ArtifactReference]
    public let referenceDesign: LogicFoundationDesignReference
    public let implementationDesign: LogicFoundationDesignReference
    public let outputSignals: [String]
    public let valueDomain: LogicUnboundedTemporalEquivalenceDomain
    public let stateSpaceLimit: Int
    public let transitionLimit: Int
    public let timeoutNanoseconds: UInt64
    public let clockSignal: String?
    public let artifactDirectory: String?

    public init(
        runID: String,
        referenceDesign: LogicFoundationDesignReference,
        implementationDesign: LogicFoundationDesignReference,
        outputSignals: [String] = [],
        valueDomain: LogicUnboundedTemporalEquivalenceDomain = .twoState,
        stateSpaceLimit: Int = 65_536,
        transitionLimit: Int = 1_000_000,
        timeoutNanoseconds: UInt64 = 30_000_000_000,
        clockSignal: String? = nil,
        inputs: [ArtifactReference] = [],
        artifactDirectory: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.referenceDesign = referenceDesign
        self.implementationDesign = implementationDesign
        self.outputSignals = outputSignals
        self.valueDomain = valueDomain
        self.stateSpaceLimit = stateSpaceLimit
        self.transitionLimit = transitionLimit
        self.timeoutNanoseconds = timeoutNanoseconds
        self.clockSignal = clockSignal
        self.artifactDirectory = artifactDirectory
        var allInputs: [ArtifactReference] = []
        for artifact in [referenceDesign.artifact, implementationDesign.artifact] + inputs
            where !allInputs.contains(artifact) {
            allInputs.append(artifact)
        }
        self.inputs = allInputs
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicFoundationBoundaryError.invalidRequest(
                "unsupported unbounded equivalence request schema version \(schemaVersion)"
            )
        }
        guard !runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicFoundationBoundaryError.invalidRequest("run ID is empty")
        }
        guard !referenceDesign.topDesignName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              referenceDesign.topDesignName == implementationDesign.topDesignName else {
            throw LogicFoundationBoundaryError.invalidRequest(
                "reference and implementation designs must use the same non-empty top design"
            )
        }
        guard stateSpaceLimit > 0, transitionLimit > 0, timeoutNanoseconds > 0 else {
            throw LogicFoundationBoundaryError.invalidRequest(
                "unbounded equivalence limits must be positive"
            )
        }
        guard outputSignals.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(outputSignals).count == outputSignals.count else {
            throw LogicFoundationBoundaryError.invalidRequest(
                "output signal names must be unique and non-empty"
            )
        }
        if let clockSignal,
           clockSignal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LogicFoundationBoundaryError.invalidRequest("clock signal name is empty")
        }
        guard inputs.contains(referenceDesign.artifact),
              inputs.contains(implementationDesign.artifact) else {
            throw LogicFoundationBoundaryError.invalidRequest(
                "equivalence design artifacts must be present in the input set"
            )
        }
    }
}
