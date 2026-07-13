import Foundation
import LogicEngineCore
import CircuiteFoundation

public struct NativeLogicSynthesisAcceptanceEvaluator: LogicSynthesisAcceptanceEvaluating {
    public init() {}

    public func evaluate(
        request: LogicSynthesisEquivalenceRequest,
        evidence: LogicSynthesisEquivalenceEvidence
    ) -> LogicSynthesisAcceptanceResult {
        do {
            try request.validate()
            try evidence.validate()
            guard evidence.runID == request.runID else {
                return rejected(
                    code: "LOGIC_EQUIVALENCE_RUN_ID_MISMATCH",
                    message: "Equivalence evidence run ID does not match the synthesis request.",
                    actions: ["retain_the_same_run_identity", "rerun_equivalence"]
                )
            }
            guard evidence.sourceDesignDigest == request.sourceDesign.designDigest else {
                return rejected(
                    code: "LOGIC_EQUIVALENCE_SOURCE_DIGEST_MISMATCH",
                    message: "Equivalence evidence does not cover the synthesized source design.",
                    actions: ["refresh_equivalence_inputs", "rerun_equivalence"]
                )
            }
            guard evidence.mappedDesignDigest == request.mappedDesign.designDigest else {
                return rejected(
                    code: "LOGIC_EQUIVALENCE_MAPPED_DIGEST_MISMATCH",
                    message: "Equivalence evidence does not cover the mapped design artifact.",
                    actions: ["refresh_mapped_design_reference", "rerun_equivalence"]
                )
            }
            guard evidence.proofScope == request.proofScope else {
                return rejected(
                    code: "LOGIC_EQUIVALENCE_PROOF_SCOPE_MISMATCH",
                    message: "Equivalence evidence proof scope does not match the request.",
                    actions: ["select_the_requested_proof_scope", "rerun_equivalence"]
                )
            }
            guard evidence.status == .proved else {
                return rejected(
                    code: "LOGIC_EQUIVALENCE_NOT_PROVED",
                    message: "Equivalence evidence is not proved; synthesis remains ineligible for acceptance.",
                    actions: ["inspect_equivalence_diagnostics", "repair_design", "rerun_equivalence"]
                )
            }
            return LogicSynthesisAcceptanceResult(
                state: .accepted,
                diagnostics: [DesignDiagnostic(
                    severity: .information,
                    code: "LOGIC_SYNTHESIS_ACCEPTED",
                    message: "The mapped design is accepted for the declared equivalence proof scope.",
                    suggestedActions: ["retain_acceptance_record", "continue_to_next_flow_stage"]
                )]
            )
        } catch let error as LogicExecutionError {
            return rejected(
                code: LogicDiagnosticFactory.make(for: error).code.rawValue,
                message: error.localizedDescription,
                actions: ["repair_equivalence_request_or_evidence", "rerun_equivalence"]
            )
        } catch {
            return rejected(
                code: "LOGIC_EQUIVALENCE_ACCEPTANCE_FAILED",
                message: error.localizedDescription,
                actions: ["inspect_equivalence_artifacts", "rerun_equivalence"]
            )
        }
    }

    private func rejected(
        code: String,
        message: String,
        actions: [String]
    ) -> LogicSynthesisAcceptanceResult {
        LogicSynthesisAcceptanceResult(
            state: .rejected,
            diagnostics: [DesignDiagnostic(
                severity: .error,
                code: code,
                message: message,
                suggestedActions: actions
            )]
        )
    }
}
