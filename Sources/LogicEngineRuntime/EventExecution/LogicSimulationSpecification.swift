import CircuiteFoundation
import LogicKernelCore

public struct LogicSimulationSpecification: Sendable, Hashable, Codable {
    public struct Assertion: Sendable, Hashable, Codable {
        public let id: String
        public let observationIndex: Int
        public let time: UInt64
        public let portIndex: Int
        public let expectedValue: String
        public init(id: String, observationIndex: Int, time: UInt64, portIndex: Int, expectedValue: String) {
            self.id = id; self.observationIndex = observationIndex; self.time = time
            self.portIndex = portIndex; self.expectedValue = expectedValue
        }
    }
    public let schemaVersion: Int
    public let designInputs: [ArtifactReference]
    public let logicalSourceNames: [String]
    public let roots: [String]
    public let top: String
    public let events: [LogicSimulationEventRecord]
    public let assertions: [Assertion]
    public init(designInputs: [ArtifactReference], logicalSourceNames: [String] = [], roots: [String] = [], top: String = "",
                events: [LogicSimulationEventRecord], assertions: [Assertion]) {
        schemaVersion = 1; self.designInputs = designInputs; self.logicalSourceNames = logicalSourceNames; self.roots = roots
        self.top = top; self.events = events; self.assertions = assertions
    }
    internal func validate(for request: LogicSimulationRequest, context: inout LogicKernelContext) throws {
        guard schemaVersion == 1, designInputs == request.designInputs,
              logicalSourceNames == request.sources.map(\.logicalName),
              roots == request.roots, top == request.top, events == request.events else {
            throw LogicKernelError.invalidInput("Simulation specification differs from exact design or stimuli")
        }
        guard !assertions.isEmpty else { throw LogicKernelError.invalidInput("Simulation specification requires assertions") }
        var ids = Set<String>()
        for assertion in assertions {
            try context.charge(.workUnits)
            guard !assertion.id.isEmpty, ids.insert(assertion.id).inserted,
                  assertion.observationIndex >= 0, assertion.portIndex >= 0,
                  !assertion.expectedValue.isEmpty else {
                throw LogicKernelError.invalidInput("Invalid or duplicate simulation assertion")
            }
            try context.observeBitWidth(UInt64(assertion.expectedValue.utf8.count))
            for byte in assertion.expectedValue.utf8 {
                try context.charge(.workUnits)
                guard byte == 48 || byte == 49 || byte == 88 || byte == 120 || byte == 90 || byte == 122 else {
                    throw LogicKernelError.invalidInput("Expected simulation values contain only 0, 1, x and z")
                }
            }
        }
    }
}
