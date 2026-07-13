import Foundation

public enum LogicExecutionError: Error, Sendable, Hashable, LocalizedError {
    case invalidLogicValue(String)
    case emptyLogicVector
    case invalidSignalWidth(Int)
    case vectorWidthMismatch(expected: Int, actual: Int)
    case missingNodeInput
    case missingArtifact(String)
    case unreadableArtifact(String)
    case artifactDigestMismatch(String)
    case artifactByteCountMismatch(String)
    case invalidArtifact(String)
    case invalidDesign(String)
    case invalidStimulus(String)
    case unsupportedNode(nodeID: String, kind: String)
    case unknownSignal(String)
    case missingOutput(String)
    case combinationalCycle
    case missingPrerequisite(String)
    case unqualifiedCell(String)
    case constraintViolation(String)
    case unsupportedWaveform(String)
    case artifactWriteFailed(String)
    case timedOut(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidLogicValue(let value): return "Unsupported logic value: \(value)."
        case .emptyLogicVector: return "A logic vector must contain at least one bit."
        case .invalidSignalWidth(let width): return "Signal width must be positive; received \(width)."
        case .vectorWidthMismatch(let expected, let actual): return "Logic vector width mismatch: expected \(expected), received \(actual)."
        case .missingNodeInput: return "A logic node is missing an input."
        case .missingArtifact(let path): return "Artifact is missing: \(path)."
        case .unreadableArtifact(let path): return "Artifact could not be read: \(path)."
        case .artifactDigestMismatch(let path): return "Artifact digest does not match the reference: \(path)."
        case .artifactByteCountMismatch(let path): return "Artifact byte count does not match the reference: \(path)."
        case .invalidArtifact(let message): return "Invalid logic artifact: \(message)."
        case .invalidDesign(let message): return "Invalid logic design: \(message)."
        case .invalidStimulus(let message): return "Invalid stimulus: \(message)."
        case .unsupportedNode(let nodeID, let kind): return "Node \(nodeID) uses unsupported semantics \(kind)."
        case .unknownSignal(let name): return "Unknown signal: \(name)."
        case .missingOutput(let nodeID): return "Node \(nodeID) does not provide an output."
        case .combinationalCycle: return "The combinational graph did not reach a fixed point."
        case .missingPrerequisite(let value): return "Missing prerequisite: \(value)."
        case .unqualifiedCell(let cell): return "Cell is not qualified for native mapping: \(cell)."
        case .constraintViolation(let message): return "Synthesis constraint was violated: \(message)."
        case .unsupportedWaveform(let format): return "Unsupported waveform format: \(format)."
        case .artifactWriteFailed(let message): return "Could not write logic artifact: \(message)."
        case .timedOut(let message): return "Logic execution timed out: \(message)."
        case .cancelled: return "Logic execution was cancelled."
        }
    }
}
