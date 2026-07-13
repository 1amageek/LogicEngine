# LogicEngine Requirements

## Goal

Provide independently qualifiable functional simulation and logic synthesis over LogicDesign.

## Required functions

| Function | Required behavior | Priority |
|---|---|---:|
| Four-state event simulation | Execute RTL and gate logic with deterministic scheduling and explicit unknown values. | P0 |
| Stimulus and testbench execution | Apply structured stimuli, assertions and deterministic seeds. | P0 |
| Waveform export | Produce VCD or FST traces and structured assertion results. | P1 |
| RTL lowering | Lower elaborated RTL into a synthesizable internal graph. | P0 |
| Logic optimization | Perform semantics-preserving Boolean and sequential optimization. | P0 |
| Technology mapping | Map logic to qualified library cells under timing, area and power constraints. | P0 |
| Synthesis provenance | Record transformations, constraints, library and PDK digests. | P0 |
| Compatibility backends | Retain current gate simulation and Boolean mapping as explicitly limited backends. | P1 |

## Required outcomes

- Simulation and synthesis remain separate products and qualification claims.
- Synthesis emits a new immutable LogicDesign reference.
- No synthesis result is accepted without later equivalence evidence.

## Common platform requirements

- Public execution surfaces are protocol-first, Sendable and dependency-injected.
- Requests and payloads are Codable, Hashable and schema-versioned.
- Inputs and outputs use immutable CircuiteFoundation `ArtifactReference`
  artifacts.
- The native lowering, simulation, synthesis, and bounded-equivalence engines
  conform directly to Foundation-refining protocols.
- The retained Xcircuite request/envelope types are compatibility inputs only.
- Diagnostics contain a stable code, severity, affected entity and suggested actions.
- Unsupported semantics and missing prerequisites produce blocked results.
- Native and external-tool backends conform to identical request and payload schemas.
- Execution capability, corpus validation, oracle correlation, process qualification and release approval remain distinct.
- Native exhaustive finite-state equivalence emits request/report-bound proof
  certificates, counterexamples, and structured limit/timeout/unsupported
  results; it never upgrades bounded traces into an unbounded claim.
- Xcircuite owns flow construction, artifact persistence, qualification gates, repair loops, approval and resume.
- The package never imports the Xcircuite runtime or circuit-studio. The
  workspace persistence dependency is restricted to the explicit,
  package-owned flow boundary and never appears in Foundation-native
  request or result payloads.

## Required developer surfaces

- Typed API
- Deterministic JSON CLI
- Positive and negative fixtures
- Contract and parser round-trip tests
- Reference corpus
- Capability and limitation report
- Xcircuite stage adapter tests

## Native capability profile

The current native profile is intentionally explicit:

| Surface | Native profile | Unavailable semantics |
|---|---|---|
| Design input | Versioned `LogicDesignDocument` execution graph | Raw SystemVerilog parsing is owned by `LogicDesign` |
| Simulation | Four-state combinational/sequential event kernel with comparisons, division/modulo, and level-sensitive latches | Unknown node kinds are `blocked` |
| Stimulus | Timestamped assignments and assertions | Malformed or width-incompatible stimulus is `failed` |
| Waveform | Deterministic VCD | FST is `blocked` until an FST writer is qualified |
| Synthesis | Buffer elimination, qualified-cell mapping, area/power/depth checks | Missing or unqualified cells are `blocked` |
| Equivalence | Bounded traces plus exact finite-state proof for declared two-state/four-state execution graphs | Arbitrary SystemVerilog/DFT proof views require an external qualified backend |
| Acceptance | Provenance always records `equivalenceRequired` | Mapped design is not accepted without later equivalence evidence |

This profile is the capability boundary for the native implementation. It must not
be reported as foundry or process qualification until corpus, oracle, and
process-scoped evidence are attached.
