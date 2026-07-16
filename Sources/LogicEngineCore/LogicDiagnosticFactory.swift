import CircuiteFoundation

public enum LogicDiagnosticFactory {
    public static func make(
        for error: LogicExecutionError,
        entity: String? = nil
    ) -> DesignDiagnostic {
        DesignDiagnostic(
            code: .trusted(code(for: error)),
            severity: .error,
            summary: error.localizedDescription,
            detail: entity.map { "entity=\($0)" },
            suggestedActions: suggestedActions(for: error).map {
                SuggestedAction(code: "logic.action.\($0)", summary: $0)
            }
        )
    }

    public static func status(for error: LogicExecutionError) -> LogicExecutionStatus {
        switch error {
        case .unsupportedNode, .missingPrerequisite, .unsupportedWaveform, .timedOut:
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
        case .artifactReadOutsideRoot:
            return "LOGIC_ARTIFACT_INPUT_OUTSIDE_ROOT"
        case .artifactOutputOutsideRoot:
            return "LOGIC_ARTIFACT_OUTPUT_OUTSIDE_ROOT"
        case .artifactSymlinkEscape:
            return "LOGIC_ARTIFACT_SYMLINK_ESCAPE"
        case .artifactCollision:
            return "LOGIC_ARTIFACT_IMMUTABLE_COLLISION"
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
        case .artifactReadOutsideRoot:
            return ["select_input_below_project_root", "remove_unsafe_symbolic_link"]
        case .artifactOutputOutsideRoot, .artifactSymlinkEscape:
            return ["select_output_below_project_root", "remove_unsafe_symbolic_link"]
        case .artifactCollision:
            return ["use_a_new_run_artifact_path", "preserve_existing_immutable_artifact"]
        case .unsupportedNode:
            return ["lower_unsupported_node", "select_backend_with_required_semantics"]
        case .missingPrerequisite:
            return ["provide_required_artifact", "run_prerequisite_stage"]
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
