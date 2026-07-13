import Foundation

public struct LogicStimulusEvent: Sendable, Hashable, Codable {
    public var time: Int64
    public var assignments: [String: LogicVector]

    public init(time: Int64, assignments: [String: LogicVector]) {
        self.time = time
        self.assignments = assignments
    }
}
