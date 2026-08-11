# LogicEngine Goal Status

## Current state

**All LogicEngine-owned milestones are implemented for the declared native
execution-graph profile. The package provides shared four-state execution,
exact finite-state temporal proof, retained corpus observations, and independent
oracle correlation. It emits evidence but does not own process/tool
qualification or a release gate. General SystemVerilog/DFT solver coverage and
foundry-specific qualification remain external scopes.**

| Maturity gate | Status | Evidence |
|---|---|---|
| Responsibility boundary | Complete | README.md and DESIGN.md |
| Public package products | Implemented | Package.swift |
| CircuiteFoundation request/result contract | Implemented for lowering, simulation, synthesis, bounded equivalence, and exhaustive finite-state equivalence | Content-only `ArtifactReference` lineage is separated from execution-scoped `LogicArtifactBinding`; results emit content-addressed evidence |
| Artifact persistence trust boundary | Implemented | Input and configured output roots are read-admitted after symlink resolution; publication is atomic; descriptor drift, digest tampering, escape and immutable collision produce typed errors |
| Contract build | Passed | Timeout-bounded `xcodebuild build` for the library and CLI schemes |
| Contract test build | Passed | Timeout-bounded `xcodebuild build-for-testing -scheme LogicEngine-Package -destination 'platform=macOS'` |
| CLI behavioral lanes | Passed for retained native profile | Lowering, simulation, synthesis, bounded equivalence, unbounded equivalence, native evidence corpus and unbounded evidence corpus execute from canonical schema-v2/v3 fixtures |
| Domain implementation | Native graph profile plus deterministic lowering, generic combinational processes, vector/NBA/reset/topology, scalar/vector logical operations, comparisons, signed arithmetic, division/modulo, arithmetic-shift semantics, both clock edges, asynchronous reset, and level-sensitive latch semantics | `NativeLogicDesignLowering`, shared `LogicExecutionGraphEvaluator`, simulation, synthesis, exhaustive equivalence |
| CLI implementation | Implemented | `lower`, `simulate`, `synthesize`, `bounded-equivalence`, `unbounded-equivalence`, and `assess-evidence` execute the canonical domain contracts |
| Fixture corpus | Retained native and exhaustive-proof corpus runner and CLI baseline | `Tests/LogicEngineTests/Fixtures`, retained suites, evidence tests, and persisted `logic-evidence-report.json` artifacts |
| Oracle correlation | Verified for retained native fixture profile | Independent observation fixtures can advance `LogicEvidenceReport` to `oracleCorrelated` |
| Tool/process qualification | External | ToolQualification consumes LogicEngine observations and owns trust evaluation |
| Flow composition boundary | Direct protocol consumption | LogicEngine remains standalone; Xcircuite and other consumers invoke its typed protocols directly |
| Release readiness | External policy | DesignFlowKernel/Xcircuite consume LogicEngine evidence together with ToolQualification decisions and human approval |

## Function status

| Function | Contract | Implementation | Validation corpus | Qualification |
|---|---|---|---|---|
| Four-state event simulation | Contract defined | Native graph profile, concat/slice/case equality, scalar/vector logical operations and logical NOT, comparisons, division/modulo, unsigned/signed arithmetic, arithmetic right shift, synchronous/asynchronous reset, positive/negative-edge sampled updates, level-sensitive latches, driver/cycle validation | Positive/negative/vector/NBA/case/logical/comparison/arithmetic/signed/reset/latch/driver/cycle/width fixtures | Raw evidence emitted; trust external |
| Stimulus and testbench execution | Contract defined | Structured events/assertions | Deterministic fixture | No oracle correlation |
| Waveform export | Contract defined | VCD; FST explicitly blocked | VCD artifact assertion | FST unavailable |
| RTL lowering | Contract defined | Snapshot-to-graph lowering with generic combinational processes, concat/slice/plain case, logical/comparison/arithmetic/division/modulo nodes, signed literals, positive/negative-edge sequential scheduling, asynchronous-reset metadata, and level-sensitive latch nodes | Parsed RTL, always-star, explicit sensitivity list, DFF/reset, signed arithmetic, logical/comparison/division/modulo, latch, blocked semantics, driver conflict, deterministic bytes, simulation handoff | Retained native evidence corpus |
| Logic optimization | Contract defined | Deterministic buffer elimination | Mapped-design test | No equivalence oracle |
| Technology mapping | Contract defined | Qualified JSON/limited Liberty mapping | Qualified/unqualified fixtures | No process qualification |
| Synthesis provenance | Contract defined | Transformation, digest provenance, typed equivalence request, and pending acceptance state | Provenance/equivalence-request artifact test | Equivalence still required |
| Synthesis acceptance gate | Contract defined | Matching proved evidence can advance to accepted; mismatched/unproved evidence is rejected | Acceptance evaluator regression | No process qualification |
| Bounded temporal equivalence | Contract defined | Same finite stimulus is simulated against two execution designs; output traces are compared within an explicit sample bound and digest-bearing reports/counterexamples are persisted | Native tests plus CLI fixture execution | Bounded native profile |
| Exhaustive finite-state temporal equivalence | Contract defined | Exact two-state/four-state enumeration of combinational, DFF, and latch transition relations with state/transition/timeout limits, report, certificate, counterexample, and structured blocked results | Native tests, retained unbounded corpus, and CLI evidence assessment | Native evidence available; trust external |
| Evidence assessment | Contract defined | `unassessed → corpusChecked → oracleCorrelated` with report and independent-observation validation | Evidence tests, retained suites, and CLI report artifact | ToolQualification owns later trust decisions |
| External backends | Protocol extension point defined | Implementations conform directly to the domain protocol | Contract tests | External backend not selected |

## Goal progression

```text
contract scaffold
      ↓
narrow implementation
      ↓
negative-path fixtures
      ↓
corpus validation
      ↓
reference-oracle correlation
      ↓
ToolQualification trust policy
      ↓
flow-owned release policy
```

## Completion definition

The narrow native execution graph and canonical execution boundary are
complete for the retained product set. The broader LogicEngine
platform goal is complete only when the milestones in `MILESTONES.md` have
passed their implementation, corpus, integration, equivalence, and evidence
exit criteria. Tool/process qualification is not a LogicEngine completion gate.

## Current blockers

- Full SystemVerilog parsing/elaboration is owned by `LogicDesign`; arbitrary RTL lowering is not yet supported by the current LogicEngine profile.
- Hierarchy, wildcard case semantics, unsupported arithmetic widths, sequential blocking assignments, unsupported multi-event clock sensitivity, and dynamic projections remain explicit blocked boundaries. Plain case, scalar/vector logical operations and logical NOT, comparisons, static concatenation/indexing/part-select, unsigned/signed arithmetic within the 64-bit profile, division/modulo, signed literals, synchronous/asynchronous reset paths, positive/negative-edge non-blocking lowering, and level-sensitive latch lowering are implemented.
- No external solver or foundry-specific process has been selected or qualified; those are outside the native LogicEngine scope.
- The native finite-state proof is exact only for the declared execution graph, value domain, and limits; it is not arbitrary SystemVerilog or DFT theorem proving.
- The separate Xcircuite/RTLVerification/ToolQualification layers still own orchestration, external solver trust, review/resume policy, and production process gates.

This file must be updated by implementation agents whenever a maturity gate changes. A source file or type name alone is never evidence of implementation or qualification.
