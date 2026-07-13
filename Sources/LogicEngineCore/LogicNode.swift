import Foundation

public struct LogicNode: Sendable, Hashable, Codable {
    public var id: String
    public var kind: LogicNodeKind
    public var inputs: [String]
    public var outputs: [String]
    public var parameters: [String: String]

    public init(
        id: String,
        kind: LogicNodeKind,
        inputs: [String],
        outputs: [String],
        parameters: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.inputs = inputs
        self.outputs = outputs
        self.parameters = parameters
    }
}
