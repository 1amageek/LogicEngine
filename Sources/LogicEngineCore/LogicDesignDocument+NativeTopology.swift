import Foundation

public extension LogicDesignDocument {
    /// Validates the single-driver, acyclic topology required by the native execution profile.
    func validateNativeExecutionTopology() throws {
        var driversBySignal: [String: [String]] = [:]
        for node in nodes {
            for output in node.outputs {
                driversBySignal[output, default: []].append(node.id)
            }
            if let resetSignal = node.parameters["resetSignal"] {
                let width = try signalWidth(named: resetSignal)
                guard width == 1 else {
                    throw LogicExecutionError.invalidDesign(
                        "reset signal \(resetSignal) for node \(node.id) must be scalar"
                    )
                }
            }
            if let resetEdge = node.parameters["resetEdge"] {
                guard node.parameters["resetSignal"] != nil else {
                    throw LogicExecutionError.invalidDesign(
                        "reset edge for node \(node.id) requires a reset signal"
                    )
                }
                guard resetEdge == "positive" || resetEdge == "negative" else {
                    throw LogicExecutionError.invalidDesign(
                        "reset edge \(resetEdge) for node \(node.id) is unsupported"
                    )
                }
            }
            if let resetValue = node.parameters["resetValue"] {
                guard node.parameters["resetEdge"] != nil else {
                    throw LogicExecutionError.invalidDesign(
                        "reset value for node \(node.id) requires an asynchronous reset edge"
                    )
                }
                guard let outputSignal = node.outputs.first else {
                    throw LogicExecutionError.missingOutput(node.id)
                }
                let outputWidth = try signalWidth(named: outputSignal)
                let vector = try LogicVector(string: resetValue)
                _ = try vector.broadcast(to: outputWidth)
            }
        }
        if let conflict = driversBySignal
            .filter({ $0.value.count > 1 })
            .sorted(by: { $0.key < $1.key })
            .first {
            throw LogicExecutionError.invalidDesign(
                "signal \(conflict.key) has multiple drivers: \(conflict.value.sorted().joined(separator: ", "))"
            )
        }

        let combinationalNodes = nodes.filter { !$0.kind.isSequential }
        let combinationalDriverBySignal = Dictionary(
            combinationalNodes.flatMap { node in node.outputs.map { ($0, node.id) } },
            uniquingKeysWith: { first, _ in first }
        )
        let adjacency = Dictionary(
            uniqueKeysWithValues: combinationalNodes.map { node in
                let predecessors = node.inputs.compactMap { combinationalDriverBySignal[$0] }
                return (node.id, Array(Set(predecessors)).sorted())
            }
        )
        var colors: [String: Int] = [:]
        for node in combinationalNodes.sorted(by: { $0.id < $1.id }) {
            if colors[node.id, default: 0] == 0 {
                try visitNativeCombinationalNode(node.id, adjacency: adjacency, colors: &colors)
            }
        }
    }

    private func visitNativeCombinationalNode(
        _ nodeID: String,
        adjacency: [String: [String]],
        colors: inout [String: Int]
    ) throws {
        colors[nodeID] = 1
        for predecessor in adjacency[nodeID] ?? [] {
            switch colors[predecessor, default: 0] {
            case 1:
                throw LogicExecutionError.combinationalCycle
            case 0:
                try visitNativeCombinationalNode(predecessor, adjacency: adjacency, colors: &colors)
            default:
                continue
            }
        }
        colors[nodeID] = 2
    }
}
