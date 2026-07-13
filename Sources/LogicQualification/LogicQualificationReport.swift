import Foundation

public struct LogicQualificationReport: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var suiteID: String
    public var implementationID: String
    public var implementationVersion: String
    public var state: LogicQualificationState
    public var evaluations: [LogicQualificationCaseEvaluation]
    public var blockers: [String]
    public var limitations: [String]
    public var checkedAt: Date
    public var oracleCorrelation: LogicQualificationOracleCorrelationReport?
    public var processQualification: LogicQualificationProcessEvidence?
    public var releaseApproval: LogicQualificationReleaseApproval?

    public init(
        suiteID: String,
        implementationID: String,
        implementationVersion: String,
        state: LogicQualificationState,
        evaluations: [LogicQualificationCaseEvaluation],
        blockers: [String] = [],
        limitations: [String] = [],
        checkedAt: Date = Date(),
        oracleCorrelation: LogicQualificationOracleCorrelationReport? = nil,
        processQualification: LogicQualificationProcessEvidence? = nil,
        releaseApproval: LogicQualificationReleaseApproval? = nil,
        schemaVersion: Int = LogicQualificationReport.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.suiteID = suiteID
        self.implementationID = implementationID
        self.implementationVersion = implementationVersion
        self.state = state
        self.evaluations = evaluations.sorted { $0.caseID < $1.caseID }
        self.blockers = Array(Set(blockers)).sorted()
        self.limitations = limitations.sorted()
        self.checkedAt = checkedAt
        self.oracleCorrelation = oracleCorrelation
        self.processQualification = processQualification
        self.releaseApproval = releaseApproval
    }

    public var corpusPassed: Bool {
        !evaluations.isEmpty && evaluations.allSatisfy(\.matched)
    }

    public var isReleaseEligible: Bool {
        guard let releaseApproval else { return false }
        do {
            try releaseApproval.validate()
        } catch {
            return false
        }
        return state == .releaseEligible
            && blockers.isEmpty
            && corpusPassed
            && oraclePassed
            && processQualification?.isUsable(for: replacingState(with: .oracleCorrelated)) == true
            && releaseApproval.approved
            && releaseApproval.suiteID == suiteID
            && releaseApproval.qualificationID == processQualification?.qualificationID
    }

    public var oraclePassed: Bool {
        oracleCorrelation?.isUsableForPromotion == true
    }

    public var processPassed: Bool {
        corpusPassed && oraclePassed && processQualification?.isUsable(for: self) == true
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicQualificationError.invalidReport(
                "unsupported report schema version \(schemaVersion)"
            )
        }
        let identities = [suiteID, implementationID, implementationVersion]
        guard identities.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw LogicQualificationError.invalidReport("report identity is incomplete")
        }
        guard !evaluations.isEmpty else {
            throw LogicQualificationError.invalidReport("report has no case evaluations")
        }

        var caseIDs: Set<String> = []
        for evaluation in evaluations {
            guard !evaluation.caseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LogicQualificationError.invalidReport("report contains an empty case ID")
            }
            guard caseIDs.insert(evaluation.caseID).inserted else {
                throw LogicQualificationError.invalidReport(
                    "report contains duplicate case \(evaluation.caseID)"
                )
            }
        }

        if let oracleCorrelation {
            guard oracleCorrelation.schemaVersion == LogicQualificationOracleCorrelationReport.currentSchemaVersion else {
                throw LogicQualificationError.invalidReport(
                    "oracle correlation schema version is unsupported"
                )
            }
            guard oracleCorrelation.suiteID == suiteID else {
                throw LogicQualificationError.invalidReport(
                    "oracle correlation suite does not match the report"
                )
            }
            guard oracleCorrelation.nativeImplementationID == implementationID else {
                throw LogicQualificationError.invalidReport(
                    "oracle correlation implementation does not match the report"
                )
            }
            let matchedCaseIDs = Set(oracleCorrelation.matchedCaseIDs)
            guard matchedCaseIDs.count == oracleCorrelation.matchedCaseIDs.count else {
                throw LogicQualificationError.invalidReport(
                    "oracle correlation contains duplicate matched cases"
                )
            }
            if oracleCorrelation.isUsableForPromotion {
                guard matchedCaseIDs == caseIDs else {
                    throw LogicQualificationError.invalidReport(
                        "usable oracle correlation does not cover the complete corpus"
                    )
                }
            }
        }

        if let processQualification {
            try processQualification.validate()
            guard processQualification.suiteID == suiteID else {
                throw LogicQualificationError.invalidReport(
                    "process qualification suite does not match the report"
                )
            }
            guard processQualification.toolImplementationID == implementationID else {
                throw LogicQualificationError.invalidReport(
                    "process qualification implementation does not match the report"
                )
            }
        }

        if let releaseApproval {
            try releaseApproval.validate()
            guard releaseApproval.suiteID == suiteID else {
                throw LogicQualificationError.invalidReport(
                    "release approval suite does not match the report"
                )
            }
            if let processQualification,
               releaseApproval.qualificationID != processQualification.qualificationID {
                throw LogicQualificationError.invalidReport(
                    "release approval does not match process qualification"
                )
            }
        }

        switch state {
        case .unassessed:
            guard !corpusPassed else {
                throw LogicQualificationError.invalidReport(
                    "an unassessed report cannot contain a passing corpus"
                )
            }
        case .corpusChecked:
            guard corpusPassed else {
                throw LogicQualificationError.invalidReport(
                    "corpusChecked requires every case to pass"
                )
            }
        case .oracleCorrelated:
            guard corpusPassed, oraclePassed else {
                throw LogicQualificationError.invalidReport(
                    "oracleCorrelated requires a passing corpus and oracle correlation"
                )
            }
        case .processQualified:
            guard corpusPassed, oraclePassed, processPassed else {
                throw LogicQualificationError.invalidReport(
                    "processQualified requires a passing corpus, oracle, and process evidence"
                )
            }
        case .releaseEligible:
            guard isReleaseEligible else {
                throw LogicQualificationError.invalidReport(
                    "releaseEligible does not satisfy all release gates"
                )
            }
        }
    }

    public func includingOracleCorrelation(
        _ correlation: LogicQualificationOracleCorrelationReport
    ) -> LogicQualificationReport {
        var result = self
        result.oracleCorrelation = correlation
        if result.corpusPassed,
           correlation.suiteID == result.suiteID,
           correlation.nativeImplementationID == result.implementationID,
           correlation.isUsableForPromotion {
            result.state = .oracleCorrelated
        } else {
            result.blockers.append("oracle_correlation_required")
            result.blockers.append(contentsOf: correlation.mismatches.map { "oracle:\($0)" })
            result.blockers = Array(Set(result.blockers)).sorted()
        }
        return result
    }

    public func includingProcessQualification(
        _ evidence: LogicQualificationProcessEvidence
    ) throws -> LogicQualificationReport {
        try evidence.validate()
        var result = self
        result.processQualification = evidence
        if result.corpusPassed && result.oraclePassed && evidence.isUsable(for: result) {
            result.state = .processQualified
        } else {
            result.blockers.append("process_qualification_required")
            result.blockers = Array(Set(result.blockers)).sorted()
        }
        return result
    }

    public func includingReleaseApproval(
        _ approval: LogicQualificationReleaseApproval
    ) throws -> LogicQualificationReport {
        try approval.validate()
        var result = self
        result.releaseApproval = approval
        guard result.state == .processQualified,
              result.corpusPassed,
              result.oraclePassed,
              result.processPassed,
              result.processQualification?.qualificationID == approval.qualificationID,
              approval.suiteID == result.suiteID,
              approval.approved else {
            result.blockers.append("release_approval_required")
            result.blockers = Array(Set(result.blockers)).sorted()
            return result
        }
        result.state = .releaseEligible
        return result
    }

    private func replacingState(
        with state: LogicQualificationState
    ) -> LogicQualificationReport {
        var result = self
        result.state = state
        return result
    }
}
