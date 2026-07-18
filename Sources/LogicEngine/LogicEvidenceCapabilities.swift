public struct LogicEvidenceCapabilities: Sendable, Hashable, Codable {
    public let retainedCorpus: Bool
    public let independentOracleCorrelation: Bool

    public init(
        retainedCorpus: Bool,
        independentOracleCorrelation: Bool
    ) {
        self.retainedCorpus = retainedCorpus
        self.independentOracleCorrelation = independentOracleCorrelation
    }

    public static let native = Self(
        retainedCorpus: true,
        independentOracleCorrelation: true
    )
}
