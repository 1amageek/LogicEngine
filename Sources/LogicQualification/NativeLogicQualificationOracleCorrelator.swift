import Foundation

public struct NativeLogicQualificationOracleCorrelator: Sendable {
    public init() {}

    public func correlate(
        nativeReport: LogicQualificationReport,
        oracle: LogicQualificationOracleObservationSet
    ) throws -> LogicQualificationOracleCorrelationReport {
        try oracle.validate()
        let independent = nativeReport.implementationID != oracle.oracleImplementationID
        var oracleByCaseID = Dictionary(uniqueKeysWithValues: oracle.observations.map { ($0.caseID, $0) })
        var matchedCaseIDs: [String] = []
        var mismatches: [String] = []
        for evaluation in nativeReport.evaluations {
            guard let oracleObservation = oracleByCaseID.removeValue(forKey: evaluation.caseID) else {
                mismatches.append("oracle_case_missing:\(evaluation.caseID)")
                continue
            }
            if evaluation.observedStatus != oracleObservation.observation.status {
                mismatches.append("status_mismatch:\(evaluation.caseID)")
            }
            if evaluation.observedDiagnosticCodes != oracleObservation.observation.diagnosticCodes {
                mismatches.append("diagnostic_mismatch:\(evaluation.caseID)")
            }
            if evaluation.observedStatus == oracleObservation.observation.status,
               evaluation.observedDiagnosticCodes == oracleObservation.observation.diagnosticCodes {
                matchedCaseIDs.append(evaluation.caseID)
            }
        }
        for caseID in oracleByCaseID.keys.sorted() {
            mismatches.append("native_case_missing:\(caseID)")
        }
        if !independent {
            mismatches.append("oracle_not_independent")
        }
        return LogicQualificationOracleCorrelationReport(
            suiteID: nativeReport.suiteID,
            nativeImplementationID: nativeReport.implementationID,
            oracleImplementationID: oracle.oracleImplementationID,
            matched: mismatches.isEmpty,
            independenceVerified: independent,
            matchedCaseIDs: matchedCaseIDs,
            mismatches: mismatches
        )
    }
}
