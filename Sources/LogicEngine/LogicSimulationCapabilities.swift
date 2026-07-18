import LogicEngineCore

public struct LogicSimulationCapabilities: Sendable, Hashable, Codable {
    public let implementation: String
    public let waveformFormats: [LogicWaveformFormat]
    public let scalarLogicalOperators: Bool
    public let vectorLogicalOperators: Bool
    public let logicalNot: Bool
    public let signedArithmetic: Bool
    public let arithmeticRightShift: Bool
    public let comparisons: Bool
    public let division: Bool
    public let modulo: Bool
    public let levelSensitiveLatch: Bool
    public let negativeEdgeSequential: Bool
    public let maximumArithmeticWidthBits: Int

    public init(
        implementation: String,
        waveformFormats: [LogicWaveformFormat],
        scalarLogicalOperators: Bool,
        vectorLogicalOperators: Bool,
        logicalNot: Bool,
        signedArithmetic: Bool,
        arithmeticRightShift: Bool,
        comparisons: Bool,
        division: Bool,
        modulo: Bool,
        levelSensitiveLatch: Bool,
        negativeEdgeSequential: Bool,
        maximumArithmeticWidthBits: Int
    ) {
        self.implementation = implementation
        self.waveformFormats = waveformFormats
        self.scalarLogicalOperators = scalarLogicalOperators
        self.vectorLogicalOperators = vectorLogicalOperators
        self.logicalNot = logicalNot
        self.signedArithmetic = signedArithmetic
        self.arithmeticRightShift = arithmeticRightShift
        self.comparisons = comparisons
        self.division = division
        self.modulo = modulo
        self.levelSensitiveLatch = levelSensitiveLatch
        self.negativeEdgeSequential = negativeEdgeSequential
        self.maximumArithmeticWidthBits = maximumArithmeticWidthBits
    }

    public static let native = Self(
        implementation: "native-four-state",
        waveformFormats: [.vcd],
        scalarLogicalOperators: true,
        vectorLogicalOperators: true,
        logicalNot: true,
        signedArithmetic: true,
        arithmeticRightShift: true,
        comparisons: true,
        division: true,
        modulo: true,
        levelSensitiveLatch: true,
        negativeEdgeSequential: true,
        maximumArithmeticWidthBits: 64
    )
}
