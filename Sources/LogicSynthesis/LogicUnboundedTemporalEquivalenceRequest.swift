import CircuiteFoundation
import Foundation
import LogicEngineCore
import LogicIR

/// Request for an exhaustive finite-state proof with no trace-length bound.
///
/// The proof is exact for the declared value domain when the complete finite
/// state/input relation fits within the declared limits. A result certificate
/// records those limits and the explored relation so callers can distinguish a
/// proof from a bounded trace experiment.
public struct LogicUnboundedTemporalEquivalenceRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = SchemaVersion.v2

    public let schemaVersion: SchemaVersion
    public let runID: String
    public let inputs: [ArtifactReference]
    public let inputBindings: [LogicArtifactBinding]
    public let referenceDesign: LogicDesignReference
    public let implementationDesign: LogicDesignReference
    public let outputSignals: [String]
    public let valueDomain: LogicUnboundedTemporalEquivalenceDomain
    public let stateSpaceLimit: Int
    public let transitionLimit: Int
    public let timeoutNanoseconds: UInt64
    public let clockSignal: String?
    public let artifactDirectory: String?

    public init(
        runID: String,
        referenceDesign: LogicDesignReference,
        implementationDesign: LogicDesignReference,
        outputSignals: [String] = [],
        valueDomain: LogicUnboundedTemporalEquivalenceDomain = .twoState,
        stateSpaceLimit: Int = 65_536,
        transitionLimit: Int = 1_000_000,
        timeoutNanoseconds: UInt64 = 30_000_000_000,
        clockSignal: String? = nil,
        inputBindings: [LogicArtifactBinding],
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
        var allBindings: [LogicArtifactBinding] = []
        for binding in inputBindings
            where !allBindings.contains(where: { $0.reference == binding.reference }) {
            allBindings.append(binding)
        }
        self.inputs = allBindings.map(\.reference)
        self.inputBindings = allBindings
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicExecutionContractError.invalidRequest(
                "unsupported unbounded equivalence request schema version \(schemaVersion)"
            )
        }
        guard !runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicExecutionContractError.invalidRequest("run ID is empty")
        }
        guard !referenceDesign.topDesignName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              referenceDesign.topDesignName == implementationDesign.topDesignName else {
            throw LogicExecutionContractError.invalidRequest(
                "reference and implementation designs must use the same non-empty top design"
            )
        }
        do {
            _ = try ContentDigest(algorithm: .sha256, hexadecimalValue: referenceDesign.designDigest)
            _ = try ContentDigest(algorithm: .sha256, hexadecimalValue: implementationDesign.designDigest)
        } catch {
            throw LogicExecutionContractError.invalidRequest(
                "equivalence designs must carry valid SHA-256 digests"
            )
        }
        guard stateSpaceLimit > 0, transitionLimit > 0, timeoutNanoseconds > 0 else {
            throw LogicExecutionContractError.invalidRequest(
                "unbounded equivalence limits must be positive"
            )
        }
        guard outputSignals.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(outputSignals).count == outputSignals.count else {
            throw LogicExecutionContractError.invalidRequest(
                "output signal names must be unique and non-empty"
            )
        }
        if let clockSignal,
           clockSignal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LogicExecutionContractError.invalidRequest("clock signal name is empty")
        }
        guard inputs.contains(referenceDesign.artifact),
              inputs.contains(implementationDesign.artifact) else {
            throw LogicExecutionContractError.invalidRequest(
                "equivalence design artifacts must be present in the input set"
            )
        }
        guard inputBindings.map(\.reference) == inputs else {
            throw LogicExecutionContractError.invalidRequest(
                "input bindings do not match the content-only input lineage"
            )
        }
        _ = try LogicArtifactBinding.require(referenceDesign.artifact, in: inputBindings)
        _ = try LogicArtifactBinding.require(implementationDesign.artifact, in: inputBindings)
    }
}
