import Foundation

public struct LogicQualificationCase: Sendable, Hashable, Codable {
    public var caseID: String
    public var request: LogicQualificationRequest
    public var expectation: LogicQualificationExpectation

    public init(
        caseID: String,
        request: LogicQualificationRequest,
        expectation: LogicQualificationExpectation
    ) {
        self.caseID = caseID
        self.request = request
        self.expectation = expectation
    }

    public func validate() throws {
        guard !caseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicQualificationError.invalidSuite("qualification case has an empty case ID")
        }
        try request.validate()
    }
}
