import Foundation

public struct LogicTransformationRecord: Sendable, Hashable, Codable {
    public var transformationID: String
    public var kind: String
    public var sourceNodeIDs: [String]
    public var resultNodeIDs: [String]
    public var rationale: String

    public init(
        transformationID: String,
        kind: String,
        sourceNodeIDs: [String],
        resultNodeIDs: [String],
        rationale: String
    ) {
        self.transformationID = transformationID
        self.kind = kind
        self.sourceNodeIDs = sourceNodeIDs
        self.resultNodeIDs = resultNodeIDs
        self.rationale = rationale
    }
}
