public struct LogicLoweringCapabilities: Sendable, Hashable, Codable {
    public let implementation: String
    public let negativeIntegerLiterals: Bool
    public let scalarLogicalOperators: Bool
    public let vectorLogicalOperators: Bool
    public let logicalNot: Bool
    public let signedArithmetic: Bool
    public let comparisons: Bool
    public let division: Bool
    public let modulo: Bool
    public let levelSensitiveLatch: Bool
    public let negativeEdgeSequential: Bool

    public init(
        implementation: String,
        negativeIntegerLiterals: Bool,
        scalarLogicalOperators: Bool,
        vectorLogicalOperators: Bool,
        logicalNot: Bool,
        signedArithmetic: Bool,
        comparisons: Bool,
        division: Bool,
        modulo: Bool,
        levelSensitiveLatch: Bool,
        negativeEdgeSequential: Bool
    ) {
        self.implementation = implementation
        self.negativeIntegerLiterals = negativeIntegerLiterals
        self.scalarLogicalOperators = scalarLogicalOperators
        self.vectorLogicalOperators = vectorLogicalOperators
        self.logicalNot = logicalNot
        self.signedArithmetic = signedArithmetic
        self.comparisons = comparisons
        self.division = division
        self.modulo = modulo
        self.levelSensitiveLatch = levelSensitiveLatch
        self.negativeEdgeSequential = negativeEdgeSequential
    }

    public static let native = Self(
        implementation: "native-rtl-to-execution-graph",
        negativeIntegerLiterals: true,
        scalarLogicalOperators: true,
        vectorLogicalOperators: true,
        logicalNot: true,
        signedArithmetic: true,
        comparisons: true,
        division: true,
        modulo: true,
        levelSensitiveLatch: true,
        negativeEdgeSequential: true
    )
}
