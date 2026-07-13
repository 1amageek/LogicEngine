import Foundation

public struct LogicDesignDocument: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var topDesignName: String
    public var ports: [LogicPort]
    public var signals: [LogicSignal]
    public var nodes: [LogicNode]
    public var metadata: [String: String]

    public init(
        schemaVersion: Int = LogicDesignDocument.currentSchemaVersion,
        topDesignName: String,
        ports: [LogicPort],
        signals: [LogicSignal],
        nodes: [LogicNode],
        metadata: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.topDesignName = topDesignName
        self.ports = ports
        self.signals = signals
        self.nodes = nodes
        self.metadata = metadata
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LogicExecutionError.invalidDesign("unsupported schema version \(schemaVersion)")
        }
        guard !topDesignName.isEmpty else {
            throw LogicExecutionError.invalidDesign("top design name is empty")
        }
        let signalNames = signals.map(\.name)
        guard Set(signalNames).count == signalNames.count else {
            throw LogicExecutionError.invalidDesign("duplicate signal name")
        }
        for signal in signals {
            guard !signal.name.isEmpty else {
                throw LogicExecutionError.invalidDesign("signal name is empty")
            }
            guard signal.width > 0 else {
                throw LogicExecutionError.invalidSignalWidth(signal.width)
            }
            if let initialValue = signal.initialValue, initialValue.width != signal.width {
                throw LogicExecutionError.vectorWidthMismatch(expected: signal.width, actual: initialValue.width)
            }
        }
        let widths = Dictionary(uniqueKeysWithValues: signals.map { ($0.name, $0.width) })
        let portNames = ports.map(\.name)
        guard Set(portNames).count == portNames.count else {
            throw LogicExecutionError.invalidDesign("duplicate port name")
        }
        for port in ports {
            guard widths[port.name] != nil else {
                throw LogicExecutionError.unknownSignal(port.name)
            }
            guard port.width == widths[port.name] else {
                throw LogicExecutionError.vectorWidthMismatch(expected: widths[port.name] ?? 0, actual: port.width)
            }
        }
        let nodeIDs = nodes.map(\.id)
        guard Set(nodeIDs).count == nodeIDs.count else {
            throw LogicExecutionError.invalidDesign("duplicate node id")
        }
        for node in nodes {
            guard !node.id.isEmpty else {
                throw LogicExecutionError.invalidDesign("node id is empty")
            }
            guard !node.outputs.isEmpty else {
                throw LogicExecutionError.missingOutput(node.id)
            }
            for signal in node.inputs + node.outputs {
                guard widths[signal] != nil else {
                    throw LogicExecutionError.unknownSignal(signal)
                }
            }
        }
    }

    public func signalWidth(named name: String) throws -> Int {
        guard let signal = signals.first(where: { $0.name == name }) else {
            throw LogicExecutionError.unknownSignal(name)
        }
        return signal.width
    }
}
