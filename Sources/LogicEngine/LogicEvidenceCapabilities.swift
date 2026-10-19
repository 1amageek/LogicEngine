public struct LogicEvidenceCapabilities: Sendable, Hashable, Codable {
    public let passiveReportValidation: Bool
    public let independentOracleCorrelation: Bool

    public static let native = Self(passiveReportValidation: true, independentOracleCorrelation: true)
}
