import Foundation
import LogicEngineCore

/// Evaluates the native finite-state execution graph without owning artifacts or run state.
///
/// The simulation engine and exhaustive equivalence engine share this evaluator so that
/// proof results cannot silently use semantics different from ordinary execution.
public struct LogicExecutionGraphEvaluator: Sendable {
    public init() {}

    public func settleCombinational(
        design: LogicDesignDocument,
        values: inout [String: LogicVector]
    ) throws {
        let combinationalNodes = design.nodes.filter { !$0.kind.isSequential }
        guard !combinationalNodes.isEmpty else { return }
        let maximumIterations = max(1, combinationalNodes.count * 4)
        for _ in 0..<maximumIterations {
            let before = values
            for node in combinationalNodes {
                let output = try evaluate(node: node, design: design, values: values)
                for signal in node.outputs {
                    values[signal] = try output.broadcast(to: design.signalWidth(named: signal))
                }
            }
            if before == values { return }
        }
        throw LogicExecutionError.combinationalCycle
    }

    public func updateSequential(
        design: LogicDesignDocument,
        values: inout [String: LogicVector],
        previousClockValues: inout [String: LogicValue],
        previousResetValues: inout [String: LogicValue]
    ) throws {
        let sampledValues = values
        var pendingValues: [String: LogicVector] = [:]
        var pendingClockValues: [String: LogicValue] = [:]
        for node in design.nodes where node.kind.isSequential {
            guard node.inputs.count >= 2 else {
                throw LogicExecutionError.missingNodeInput
            }
            guard let outputSignal = node.outputs.first else {
                throw LogicExecutionError.missingOutput(node.id)
            }
            let outputWidth = try design.signalWidth(named: outputSignal)
            guard let dataSignal = sampledValues[node.inputs[0]] else {
                throw LogicExecutionError.unknownSignal(node.inputs[0])
            }
            let data = try dataSignal.broadcast(to: outputWidth)
            if node.kind == .latch {
                let gate = try scalarValue(sampledValues[node.inputs[1]], entity: node.id)
                let level = node.parameters["level"] ?? "positive"
                let active: Bool
                switch level {
                case "positive": active = gate == .one
                case "negative": active = gate == .zero
                default:
                    throw LogicExecutionError.invalidDesign(
                        "latch node \(node.id) has unsupported active level \(level)"
                    )
                }
                let nextValue: LogicVector
                if active {
                    nextValue = data
                } else if gate == .unknown || gate == .highImpedance {
                    let current: LogicVector
                    if let existingValue = sampledValues[outputSignal] {
                        current = existingValue
                    } else {
                        current = try LogicVector.unknown(width: outputWidth)
                    }
                    nextValue = current == data ? current : (try LogicVector.unknown(width: outputWidth))
                } else {
                    if let existingValue = sampledValues[outputSignal] {
                        nextValue = existingValue
                    } else {
                        nextValue = try LogicVector.unknown(width: outputWidth)
                    }
                }
                pendingValues[outputSignal] = try nextValue.broadcast(to: outputWidth)
                continue
            }
            let clock = try scalarValue(sampledValues[node.inputs[1]], entity: node.id)
            let oldClock = previousClockValues[node.id] ?? .unknown
            let edge = node.parameters["edge"] ?? "positive"
            let isActiveEdge: Bool
            switch edge {
            case "positive":
                isActiveEdge = oldClock == .zero && clock == .one
            case "negative":
                isActiveEdge = oldClock == .one && clock == .zero
            default:
                throw LogicExecutionError.invalidDesign(
                    "sequential node \(node.id) has unsupported clock edge \(edge)"
                )
            }
            let asynchronousReset: (value: LogicValue, isActive: Bool, isUnknown: Bool)?
            if let resetSignal = node.parameters["resetSignal"], let resetEdge = node.parameters["resetEdge"] {
                let reset = try scalarValue(sampledValues[resetSignal], entity: node.id)
                let oldReset = previousResetValues[node.id] ?? .unknown
                let assertedValue: LogicValue
                switch resetEdge {
                case "positive": assertedValue = .one
                case "negative": assertedValue = .zero
                default:
                    throw LogicExecutionError.invalidDesign(
                        "sequential node \(node.id) has unsupported reset edge \(resetEdge)"
                    )
                }
                asynchronousReset = (
                    value: reset,
                    isActive: reset == assertedValue || (oldReset == .unknown && reset == assertedValue),
                    isUnknown: reset == .unknown || reset == .highImpedance
                )
            } else {
                asynchronousReset = nil
            }
            let existingValue = sampledValues[outputSignal]
            var nextValue: LogicVector
            if let existingValue {
                nextValue = existingValue
            } else {
                nextValue = try LogicVector.unknown(width: outputWidth)
            }
            if let asynchronousReset, asynchronousReset.isActive {
                if let resetValue = node.parameters["resetValue"] {
                    nextValue = try LogicVector(string: resetValue).broadcast(to: outputWidth)
                } else {
                    nextValue = try LogicVector.zero(width: outputWidth)
                }
            } else if let asynchronousReset, asynchronousReset.isUnknown {
                nextValue = try LogicVector.unknown(width: outputWidth)
            } else if asynchronousReset == nil,
                      let resetSignal = node.parameters["resetSignal"],
                      isActiveEdge {
                let reset = try scalarValue(sampledValues[resetSignal], entity: node.id)
                switch reset {
                case .one:
                    nextValue = try LogicVector.zero(width: outputWidth)
                case .unknown, .highImpedance:
                    nextValue = try LogicVector.unknown(width: outputWidth)
                case .zero:
                    nextValue = data
                }
            } else if isActiveEdge {
                nextValue = data
            } else if clock == .unknown || clock == .highImpedance {
                let current: LogicVector
                if let existingValue = sampledValues[outputSignal] {
                    current = existingValue
                } else {
                    current = try LogicVector.unknown(width: outputWidth)
                }
                nextValue = current == data ? current : (try LogicVector.unknown(width: outputWidth))
            }
            pendingValues[outputSignal] = try nextValue.broadcast(to: outputWidth)
            pendingClockValues[node.id] = clock
            if let asynchronousReset {
                previousResetValues[node.id] = asynchronousReset.value
            }
        }
        values.merge(pendingValues) { _, new in new }
        previousClockValues.merge(pendingClockValues) { _, new in new }
    }

    public func evaluate(
        node: LogicNode,
        design: LogicDesignDocument,
        values: [String: LogicVector]
    ) throws -> LogicVector {
        let outputSignal = node.outputs.first ?? ""
        let outputWidth = try design.signalWidth(named: outputSignal)
        let rawInputs = try node.inputs.map { signal in
            guard let value = values[signal] else { throw LogicExecutionError.unknownSignal(signal) }
            return value
        }
        switch node.kind {
        case .caseEqual:
            guard rawInputs.count >= 2, outputWidth == 1 else {
                throw LogicExecutionError.missingNodeInput
            }
            return try LogicVector.caseEqual(rawInputs[0], rawInputs[1])
        case .caseNotEqual:
            guard rawInputs.count >= 2, outputWidth == 1 else {
                throw LogicExecutionError.missingNodeInput
            }
            return try LogicVector.caseNotEqual(rawInputs[0], rawInputs[1])
        case .equal:
            guard rawInputs.count >= 2, outputWidth == 1 else {
                throw LogicExecutionError.missingNodeInput
            }
            return try LogicVector.logicallyEqual(rawInputs[0], rawInputs[1])
        case .notEqual:
            guard rawInputs.count >= 2, outputWidth == 1 else {
                throw LogicExecutionError.missingNodeInput
            }
            return try LogicVector.logicallyNotEqual(rawInputs[0], rawInputs[1])
        case .lessThan, .lessEqual, .greaterThan, .greaterEqual:
            guard rawInputs.count >= 2, outputWidth == 1 else {
                throw LogicExecutionError.missingNodeInput
            }
            return try LogicVector.compared(
                rawInputs[0],
                rawInputs[1],
                relation: comparisonRelation(for: node.kind),
                signed: node.parameters["signed"] == "true"
            )
        case .logicalAnd:
            guard rawInputs.count >= 2, outputWidth == 1 else {
                throw LogicExecutionError.missingNodeInput
            }
            return LogicVector.logicalAnd(rawInputs[0], rawInputs[1])
        case .logicalOr:
            guard rawInputs.count >= 2, outputWidth == 1 else {
                throw LogicExecutionError.missingNodeInput
            }
            return LogicVector.logicalOr(rawInputs[0], rawInputs[1])
        case .logicalNot:
            guard let input = rawInputs.first, outputWidth == 1 else {
                throw LogicExecutionError.missingNodeInput
            }
            return LogicVector.logicalNot(input)
        case .add:
            guard rawInputs.count >= 2 else { throw LogicExecutionError.missingNodeInput }
            return try arithmeticResult(node: node, lhs: rawInputs[0], rhs: rawInputs[1], width: outputWidth, operation: .add)
        case .subtract:
            guard rawInputs.count >= 2 else { throw LogicExecutionError.missingNodeInput }
            return try arithmeticResult(node: node, lhs: rawInputs[0], rhs: rawInputs[1], width: outputWidth, operation: .subtract)
        case .multiply:
            guard rawInputs.count >= 2 else { throw LogicExecutionError.missingNodeInput }
            return try arithmeticResult(node: node, lhs: rawInputs[0], rhs: rawInputs[1], width: outputWidth, operation: .multiply)
        case .divide:
            guard rawInputs.count >= 2 else { throw LogicExecutionError.missingNodeInput }
            return try LogicVector.divided(
                rawInputs[0],
                rawInputs[1],
                width: outputWidth,
                signed: node.parameters["signed"] == "true"
            )
        case .modulo:
            guard rawInputs.count >= 2 else { throw LogicExecutionError.missingNodeInput }
            return try LogicVector.modulo(
                rawInputs[0],
                rawInputs[1],
                width: outputWidth,
                signed: node.parameters["signed"] == "true"
            )
        case .shiftLeft:
            guard rawInputs.count >= 2 else { throw LogicExecutionError.missingNodeInput }
            return try LogicVector.shiftedLeft(rawInputs[0], by: rawInputs[1], width: outputWidth)
        case .shiftRight:
            guard rawInputs.count >= 2 else { throw LogicExecutionError.missingNodeInput }
            if node.parameters["signed"] == "true" {
                return try LogicVector.arithmeticShiftedRight(rawInputs[0], by: rawInputs[1], width: outputWidth)
            }
            return try LogicVector.shiftedRight(rawInputs[0], by: rawInputs[1], width: outputWidth)
        case .concat:
            let result = try LogicVector.concatenated(rawInputs)
            guard result.width == outputWidth else {
                throw LogicExecutionError.vectorWidthMismatch(expected: outputWidth, actual: result.width)
            }
            return result
        case .slice:
            guard let source = rawInputs.first,
                  let sourceMSB = node.parameters["sourceMSB"].flatMap(Int.init),
                  let sourceLSB = node.parameters["sourceLSB"].flatMap(Int.init),
                  let selectionMSB = node.parameters["selectionMSB"].flatMap(Int.init),
                  let selectionLSB = node.parameters["selectionLSB"].flatMap(Int.init) else {
                throw LogicExecutionError.invalidDesign("slice node \(node.id) is missing range parameters")
            }
            let result = try source.sliced(
                sourceMSB: sourceMSB,
                sourceLSB: sourceLSB,
                selectionMSB: selectionMSB,
                selectionLSB: selectionLSB
            )
            guard result.width == outputWidth else {
                throw LogicExecutionError.vectorWidthMismatch(expected: outputWidth, actual: result.width)
            }
            return result
        default:
            break
        }
        let inputs = try rawInputs.map { try $0.broadcast(to: outputWidth) }
        switch node.kind {
        case .and:
            return try LogicVector.and(inputs, width: outputWidth)
        case .or:
            return try LogicVector.or(inputs, width: outputWidth)
        case .xor:
            return try LogicVector.xor(inputs, width: outputWidth)
        case .nand:
            return try LogicVector.and(inputs, width: outputWidth).inverted()
        case .nor:
            return try LogicVector.or(inputs, width: outputWidth).inverted()
        case .xnor:
            return try LogicVector.xor(inputs, width: outputWidth).inverted()
        case .not:
            guard let input = inputs.first else { throw LogicExecutionError.missingNodeInput }
            return input.inverted()
        case .buffer:
            guard let input = inputs.first else { throw LogicExecutionError.missingNodeInput }
            return input
        case .constant:
            let text = node.parameters["value"] ?? String(repeating: "X", count: outputWidth)
            return try LogicVector(string: text).broadcast(to: outputWidth)
        case .mux:
            guard inputs.count >= 3 else { throw LogicExecutionError.missingNodeInput }
            let select = try scalarValue(inputs[0], entity: node.id)
            switch select {
            case .zero: return inputs[2]
            case .one: return inputs[1]
            case .unknown, .highImpedance: return try LogicVector.merge(inputs[1], inputs[2])
            }
        case .triState:
            guard inputs.count >= 2 else { throw LogicExecutionError.missingNodeInput }
            let enable = try scalarValue(inputs[1], entity: node.id)
            switch enable {
            case .zero: return try LogicVector(bits: Array(repeating: .highImpedance, count: outputWidth))
            case .one: return inputs[0]
            case .unknown, .highImpedance: return try LogicVector.unknown(width: outputWidth)
            }
        case .dff:
            throw LogicExecutionError.invalidDesign("sequential node evaluated as combinational")
        case .latch:
            throw LogicExecutionError.invalidDesign("sequential node evaluated as combinational")
        default:
            throw LogicExecutionError.unsupportedNode(nodeID: node.id, kind: node.kind.rawValue)
        }
    }

    private func scalarValue(_ vector: LogicVector?, entity: String) throws -> LogicValue {
        guard let vector else { throw LogicExecutionError.unknownSignal(entity) }
        guard vector.width == 1 else {
            throw LogicExecutionError.invalidDesign("node \(entity) requires scalar control signals")
        }
        return vector[0]
    }

    private enum ArithmeticOperation {
        case add
        case subtract
        case multiply
    }

    private func comparisonRelation(
        for kind: LogicNodeKind
    ) -> LogicVector.Comparison {
        switch kind {
        case .lessThan: return .lessThan
        case .lessEqual: return .lessEqual
        case .greaterThan: return .greaterThan
        case .greaterEqual: return .greaterEqual
        default: return .lessThan
        }
    }

    private func arithmeticResult(
        node: LogicNode,
        lhs: LogicVector,
        rhs: LogicVector,
        width: Int,
        operation: ArithmeticOperation
    ) throws -> LogicVector {
        let isSigned = node.parameters["signed"] == "true"
        switch (operation, isSigned) {
        case (.add, false): return try LogicVector.added(lhs, rhs, width: width)
        case (.add, true): return try LogicVector.signedAdded(lhs, rhs, width: width)
        case (.subtract, false): return try LogicVector.subtracted(lhs, rhs, width: width)
        case (.subtract, true): return try LogicVector.signedSubtracted(lhs, rhs, width: width)
        case (.multiply, false): return try LogicVector.multiplied(lhs, rhs, width: width)
        case (.multiply, true): return try LogicVector.signedMultiplied(lhs, rhs, width: width)
        }
    }
}
