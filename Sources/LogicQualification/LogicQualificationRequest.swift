import Foundation
import LogicSimulation
import LogicSynthesis

public enum LogicQualificationRequest: Sendable, Hashable, Codable {
    case simulation(LogicSimulationRequest)
    case synthesis(LogicSynthesisRequest)
    case unbounded(LogicUnboundedTemporalEquivalenceFoundationRequest)

    public var runID: String {
        switch self {
        case .simulation(let request):
            request.runID
        case .synthesis(let request):
            request.runID
        case .unbounded(let request):
            request.runID
        }
    }

    public func validate() throws {
        guard !runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LogicQualificationError.invalidSuite("qualification request has an empty run ID")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case simulation
        case synthesis
        case unbounded
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .simulation:
            self = .simulation(try container.decode(LogicSimulationRequest.self, forKey: .value))
        case .synthesis:
            self = .synthesis(try container.decode(LogicSynthesisRequest.self, forKey: .value))
        case .unbounded:
            self = .unbounded(try container.decode(
                LogicUnboundedTemporalEquivalenceFoundationRequest.self,
                forKey: .value
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .simulation(let request):
            try container.encode(Kind.simulation, forKey: .kind)
            try container.encode(request, forKey: .value)
        case .synthesis(let request):
            try container.encode(Kind.synthesis, forKey: .kind)
            try container.encode(request, forKey: .value)
        case .unbounded(let request):
            try container.encode(Kind.unbounded, forKey: .kind)
            try container.encode(request, forKey: .value)
        }
    }
}
