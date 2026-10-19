public struct LogicLoweringCapabilities: Sendable, Hashable, Codable {
    public let implementation: String
    public let typedWordLowering: Bool
    public let typedBitLowering: Bool
    public let binarySynthesisProfile: Bool

    public static let native = Self(implementation: "native-typed-word-and-bit",
        typedWordLowering: true, typedBitLowering: true, binarySynthesisProfile: true)
}
