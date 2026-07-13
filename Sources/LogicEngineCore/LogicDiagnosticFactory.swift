import Foundation
import XcircuitePackage

public enum LogicDiagnosticFactory {
    public static func make(
        for error: LogicExecutionError,
        entity: String? = nil
    ) -> XcircuiteEngineDiagnostic {
        XcircuiteEngineDiagnostic(
            severity: .error,
            code: code(for: error),
            message: error.localizedDescription,
            entity: entity,
            suggestedActions: suggestedActions(for: error)
        )
    }

    public static func status(for error: LogicExecutionError) -> XcircuiteEngineExecutionStatus {
        switch error {
        case .unsupportedNode, .missingPrerequisite, .unqualifiedCell, .unsupportedWaveform, .timedOut:
            return .blocked
        case .cancelled:
            return .cancelled
        default:
            return .failed
        }
    }

    private static func code(for error: LogicExecutionError) -> String {
        switch error {
        case .invalidLogicValue, .emptyLogicVector, .invalidSignalWidth, .vectorWidthMismatch, .missingNodeInput:
            return "LOGIC_VALUE_INVALID"
        case .missingArtifact:
            return "LOGIC_ARTIFACT_MISSING"
        case .unreadableArtifact:
            return "LOGIC_ARTIFACT_UNREADABLE"
        case .artifactDigestMismatch:
            return "LOGIC_ARTIFACT_DIGEST_MISMATCH"
        case .artifactByteCountMismatch:
            return "LOGIC_ARTIFACT_SIZE_MISMATCH"
        case .invalidArtifact:
            return "LOGIC_ARTIFACT_INVALID"
        case .invalidDesign:
            return "LOGIC_DESIGN_INVALID"
        case .invalidStimulus:
            return "LOGIC_STIMULUS_INVALID"
        case .unsupportedNode:
            return "LOGIC_SEMANTICS_UNSUPPORTED"
        case .unknownSignal:
            return "LOGIC_SIGNAL_UNKNOWN"
        case .missingOutput:
            return "LOGIC_NODE_OUTPUT_MISSING"
        case .combinationalCycle:
            return "LOGIC_COMBINATIONAL_CYCLE"
        case .missingPrerequisite:
            return "LOGIC_PREREQUISITE_MISSING"
        case .unqualifiedCell:
            return "LOGIC_CELL_UNQUALIFIED"
        case .constraintViolation:
            return "LOGIC_CONSTRAINT_VIOLATION"
        case .unsupportedWaveform:
            return "LOGIC_WAVEFORM_UNSUPPORTED"
        case .artifactWriteFailed:
            return "LOGIC_ARTIFACT_WRITE_FAILED"
        case .timedOut:
            return "LOGIC_EXECUTION_TIMEOUT"
        case .cancelled:
            return "LOGIC_EXECUTION_CANCELLED"
        }
    }

    private static func suggestedActions(for error: LogicExecutionError) -> [String] {
        switch error {
        case .missingArtifact, .unreadableArtifact, .artifactDigestMismatch, .artifactByteCountMismatch:
            return ["verify_artifact_path", "refresh_artifact_reference"]
        case .unsupportedNode:
            return ["lower_unsupported_node", "select_backend_with_required_semantics"]
        case .missingPrerequisite:
            return ["provide_required_artifact", "run_prerequisite_stage"]
        case .unqualifiedCell:
            return ["provide_process_scoped_qualification", "select_a_qualified_cell"]
        case .constraintViolation:
            return ["relax_or_update_constraints", "optimize_the_design"]
        case .combinationalCycle:
            return ["inspect_combinational_feedback", "insert_a_sequential_boundary"]
        case .cancelled:
            return ["resume_with_the_same_run_inputs"]
        case .timedOut:
            return ["increase_timeout_budget", "reduce_declared_state_or_input_space"]
        default:
            return ["inspect_structured_diagnostic"]
        }
    }
}
