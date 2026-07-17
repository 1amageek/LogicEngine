import Foundation

public struct LogicEvidenceCase: Sendable, Hashable, Codable {
    public var caseID: String
    public var request: LogicEvidenceRequest
    public var expectation: LogicEvidenceExpectation

    public init(
        caseID: String,
        request: LogicEvidenceRequest,
        expectation: LogicEvidenceExpectation
    ) {
        self.caseID = caseID
        self.request = request
        self.expectation = expectation
    }

    public func validate() throws {
        guard !caseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicEvidenceError.invalidSuite("evidence case has an empty case ID")
        }
        try request.validate()
    }
}
