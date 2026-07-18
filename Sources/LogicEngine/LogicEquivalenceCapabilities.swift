import LogicEngineCore

public struct LogicEquivalenceCapabilities: Sendable, Hashable, Codable {
    public let implementation: String
    public let boundedTemporalTrace: Bool
    public let unboundedTemporalFormal: Bool
    public let unboundedImplementation: String
    public let unboundedProofCertificate: Bool
    public let waveformFormats: [LogicWaveformFormat]

    public init(
        implementation: String,
        boundedTemporalTrace: Bool,
        unboundedTemporalFormal: Bool,
        unboundedImplementation: String,
        unboundedProofCertificate: Bool,
        waveformFormats: [LogicWaveformFormat]
    ) {
        self.implementation = implementation
        self.boundedTemporalTrace = boundedTemporalTrace
        self.unboundedTemporalFormal = unboundedTemporalFormal
        self.unboundedImplementation = unboundedImplementation
        self.unboundedProofCertificate = unboundedProofCertificate
        self.waveformFormats = waveformFormats
    }

    public static let native = Self(
        implementation: "native-bounded-trace",
        boundedTemporalTrace: true,
        unboundedTemporalFormal: true,
        unboundedImplementation: "native-exhaustive-finite-state",
        unboundedProofCertificate: true,
        waveformFormats: [.vcd]
    )
}
