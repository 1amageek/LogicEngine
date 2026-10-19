public struct LogicOptimizationStatistics: Sendable, Equatable {
    public let sourceNodes: Int
    public let resultNodes: Int
    public let constantFolds: Int
    public let commonSubexpressions: Int
    public var removedNodes: Int { sourceNodes - resultNodes }
    internal init(sourceNodes: Int, resultNodes: Int, constantFolds: Int, commonSubexpressions: Int) {
        self.sourceNodes = sourceNodes; self.resultNodes = resultNodes
        self.constantFolds = constantFolds; self.commonSubexpressions = commonSubexpressions
    }
}
