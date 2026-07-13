import Foundation
import LogicEngineCore

public struct LogicUnboundedTemporalEquivalenceCertificate: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let requestDigest: String
    public let reportDigest: String
    public let solverID: String
    public let solverVersion: String
    public let proofScope: String
    public let valueDomain: LogicUnboundedTemporalEquivalenceDomain
    public let exploredStateCount: Int
    public let exploredTransitionCount: Int
    public let complete: Bool
    public let status: LogicUnboundedTemporalEquivalenceStatus

    public init(
        requestDigest: String,
        reportDigest: String,
        solverID: String,
        solverVersion: String,
        proofScope: String,
        valueDomain: LogicUnboundedTemporalEquivalenceDomain,
        exploredStateCount: Int,
        exploredTransitionCount: Int,
        complete: Bool,
        status: LogicUnboundedTemporalEquivalenceStatus,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.requestDigest = requestDigest
        self.reportDigest = reportDigest
        self.solverID = solverID
        self.solverVersion = solverVersion
        self.proofScope = proofScope
        self.valueDomain = valueDomain
        self.exploredStateCount = exploredStateCount
        self.exploredTransitionCount = exploredTransitionCount
        self.complete = complete
        self.status = status
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion,
              !requestDigest.isEmpty,
              !reportDigest.isEmpty,
              !solverID.isEmpty,
              !solverVersion.isEmpty,
              !proofScope.isEmpty,
              exploredStateCount >= 0,
              exploredTransitionCount >= 0 else {
            throw LogicExecutionError.invalidArtifact(
                "unbounded temporal equivalence certificate identity is incomplete"
            )
        }
        if complete {
            guard status == .proved else {
                throw LogicExecutionError.invalidArtifact(
                    "a complete certificate must carry a proved status"
                )
            }
        }
    }

    public func validateBinding(
        requestDigest: String,
        reportDigest: String
    ) throws {
        try validate()
        guard self.requestDigest == requestDigest,
              self.reportDigest == reportDigest else {
            throw LogicExecutionError.invalidArtifact(
                "unbounded temporal equivalence certificate binding does not match its inputs"
            )
        }
    }
}
