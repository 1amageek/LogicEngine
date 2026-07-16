import Foundation

public struct LogicEvidenceReport: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var suiteID: String
    public var implementationID: String
    public var implementationVersion: String
    public var state: LogicEvidenceState
    public var evaluations: [LogicEvidenceCaseEvaluation]
    public var blockers: [String]
    public var limitations: [String]
    public var checkedAt: Date
    public var oracleCorrelation: LogicEvidenceOracleCorrelationReport?

    public init(
        suiteID: String,
        implementationID: String,
        implementationVersion: String,
        state: LogicEvidenceState,
        evaluations: [LogicEvidenceCaseEvaluation],
        blockers: [String] = [],
        limitations: [String] = [],
        checkedAt: Date = Date(),
        oracleCorrelation: LogicEvidenceOracleCorrelationReport? = nil,
        schemaVersion: Int = LogicEvidenceReport.currentSchemaVersion
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
    }

    public var corpusPassed: Bool {
        !evaluations.isEmpty && evaluations.allSatisfy(\.matched)
    }

    public var oraclePassed: Bool {
        oracleCorrelation?.isUsableForPromotion == true
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicEvidenceError.invalidReport(
                "unsupported report schema version \(schemaVersion)"
            )
        }
        let identities = [suiteID, implementationID, implementationVersion]
        guard identities.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw LogicEvidenceError.invalidReport("report identity is incomplete")
        }
        guard !evaluations.isEmpty else {
            throw LogicEvidenceError.invalidReport("report has no case evaluations")
        }

        var caseIDs: Set<String> = []
        for evaluation in evaluations {
            guard !evaluation.caseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LogicEvidenceError.invalidReport("report contains an empty case ID")
            }
            guard caseIDs.insert(evaluation.caseID).inserted else {
                throw LogicEvidenceError.invalidReport(
                    "report contains duplicate case \(evaluation.caseID)"
                )
            }
        }

        if let oracleCorrelation {
            guard oracleCorrelation.schemaVersion == LogicEvidenceOracleCorrelationReport.currentSchemaVersion else {
                throw LogicEvidenceError.invalidReport(
                    "oracle correlation schema version is unsupported"
                )
            }
            guard oracleCorrelation.suiteID == suiteID else {
                throw LogicEvidenceError.invalidReport(
                    "oracle correlation suite does not match the report"
                )
            }
            guard oracleCorrelation.nativeImplementationID == implementationID else {
                throw LogicEvidenceError.invalidReport(
                    "oracle correlation implementation does not match the report"
                )
            }
            let matchedCaseIDs = Set(oracleCorrelation.matchedCaseIDs)
            guard matchedCaseIDs.count == oracleCorrelation.matchedCaseIDs.count else {
                throw LogicEvidenceError.invalidReport(
                    "oracle correlation contains duplicate matched cases"
                )
            }
            if oracleCorrelation.isUsableForPromotion {
                guard matchedCaseIDs == caseIDs else {
                    throw LogicEvidenceError.invalidReport(
                        "usable oracle correlation does not cover the complete corpus"
                    )
                }
            }
        }

        switch state {
        case .unassessed:
            guard !corpusPassed else {
                throw LogicEvidenceError.invalidReport(
                    "an unassessed report cannot contain a passing corpus"
                )
            }
        case .corpusChecked:
            guard corpusPassed else {
                throw LogicEvidenceError.invalidReport(
                    "corpusChecked requires every case to pass"
                )
            }
        case .oracleCorrelated:
            guard corpusPassed, oraclePassed else {
                throw LogicEvidenceError.invalidReport(
                    "oracleCorrelated requires a passing corpus and oracle correlation"
                )
            }
        }
    }

    public func includingOracleCorrelation(
        _ correlation: LogicEvidenceOracleCorrelationReport
    ) -> LogicEvidenceReport {
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

}
