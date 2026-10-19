# LogicEngine Interface Contract

## Common shape

Host Runtime execution protocols refine `CircuiteFoundation.Engine` with one
domain request/result pair. Portable kernels expose synchronous typed-throwing
requirements with a caller-owned cumulative context. Runtime requests carry a
`SchemaVersion`, run ID and digest-bearing `ArtifactReference` values. Results
retain domain metrics and exact evidence/provenance.

## Products

### LogicLowering

Portable procedural and word-to-bit kernels. Component contracts are linked below.

### LogicSimulation

Event-driven RTL and gate simulation.

### LogicSynthesis

Optimization and technology mapping.

### LogicEngine

Umbrella product without a combined execution protocol.
`LogicEngineCapabilities` is the typed, versioned discovery record returned by
the CLI. Its `schemaVersion` belongs to that record rather than to a package API
namespace, and its domain capability fields are Codable values rather than an
untyped JSON dictionary. [Public product design](Sources/LogicEngine/DESIGN.md)
owns the current discovery field/version contract.

### LogicEvidence

[LogicEvidence](Sources/LogicEvidence/DESIGN.md) exposes passive report and
oracle observation values. `NativeLogicEvidenceOracleCorrelator` compares caller-
supplied reports with independent observations; executable suites and runners
are retired.

`LogicEvidenceReport` records only `unassessed`, `corpusChecked`, and
`oracleCorrelated` maturity. It validates suite, implementation, case, and
independent-observation identity, but it cannot promote itself to process trust
or release eligibility. ToolQualification consumes these retained observations
with tool, environment, and process evidence. DesignFlowKernel and Xcircuite own
release policy, approval, and resume.

## Native implementations

The current Xcircuite `LogicEquivalenceFlowStageExecutor` consumes a schema-v3
`LogicEquivalenceRequest` and uses Runtime's checked receipt reload. Its contract is
[ActualCellStages](../Xcircuite/Sources/Xcircuite/ActualCellStages/DESIGN.md).
Retained structural comparison requests do not establish actual-cell equivalence.

## Error contract

Current Runtime commands return completed results only after checked publication.
Invalid input, unsupported semantics, exceeded limits, cancellation, deadline,
proof/STA failure and persistence failure throw distinguishable kernel/host errors.
The CLI converts these failures into nonzero structured diagnostics.

## Flow integration

The Xcircuite-owned stage executor must:

1. resolve project-relative references through the injected Xcircuite workspace store;
2. verify input digests;
3. evaluate ToolQualification requirements;
4. invoke the injected engine protocol;
5. persist every returned artifact;
6. map diagnostics and status to FlowStageResult;
7. attach design, PDK and tool provenance;
8. persist review and audit artifacts with a request digest;
9. reuse a valid persisted equivalence result only after validating the result,
   evidence, acceptance, review, audit, and file integrity contracts.

## LogicDesign host/portable dependency boundary

LogicIR is the portable value/validation dependency. Host codecs and Codable
conformances are supplied by LogicDesignSerialization; host regression parsing
uses LogicDesign's retained parser. Exact revisions remain URL pins in Package.swift.
Local mirrors are verification configuration, not release dependencies.

## Portable word-to-bit lowering

`LogicLowering.LogicBitLowering.lower(_:context:)` is a synchronous typed-throws
requirement implemented by NativeLogicBitLowering. It borrows validated immutable
WordLogicDesign and returns validated BitLogicDesign while retaining the same run
context. [BitExpansion](Sources/LogicLowering/BitExpansion/DESIGN.md) owns arithmetic,
state ordering, origins and bounded failure guarantees.

Legacy host lowering APIs and commands are removed. No metadata execution graph
is accepted by the portable kernel and no host serialization dependency enters
the portable target.

## Portable procedural lowering

`LogicLowering.LogicWordLowering.lower(_:context:)` borrows ElaboratedRTL and
returns validated WordLogicDesign. NativeLogicWordLowering owns ordered blocking,
NBA, branch/partial-write and state-control conversion through
[ProceduralLowering](Sources/LogicLowering/ProceduralLowering/DESIGN.md). The same
cumulative context is then passed to LogicBitLowering. Neither kernel implies
complete source-subset elaboration, mapped-cell proof or four-state equivalence.

## Host technology library compilation

`LogicEngineRuntime.LogicTechnologyLibraryCompiling.compile` consumes TimingCore
owned Liberty facts, an exact source ArtifactID, explicit canonical identity base
and the cumulative kernel context. The immutable result contains an optional
validated actual-cell library and every source cell's positioned eligibility.
No eligible cells yields no library; resource and identity failures throw typed
errors. [TechnologyLibraryCompilation](Sources/LogicEngineRuntime/TechnologyLibraryCompilation/DESIGN.md)
owns the admission and ownership contract. Import this host-only product directly.

## Actual-cell event simulation

`LogicSimulation` is portable; compile validated MappedGateDesign with its exact
library, create noncopyable model-bound state, then evaluate ordered input events
through protocol requirements. [CellEvents](Sources/LogicSimulation/CellEvents/DESIGN.md)
owns the truth/edge/reset/latch and failure-lifecycle contracts. The legacy host
metadata evaluator is retired. Metadata graph artifacts are not accepted by the
current model compiler.

## Portable Technology Mapping
`LogicSynthesis.LogicTechnologyMapping.map(_:library:policy:context:)` borrows validated bit/library owners and returns an immutable unverified LogicMappingCandidate with actual physical pins, retained source/origins and actual instance area/depth. NativeLogicTechnologyMapper implements the synchronous typed-throws requirement. Policy explicitly owns cut-input, cell search-input and cut-count bounds and generated identity start. [TechnologyMapping](Sources/LogicSynthesis/TechnologyMapping/DESIGN.md) owns the contract; LogicProof independently verifies the original bit graph against the actual library-bound netlist. Runtime owns host CLI/artifact composition.

## Schema-v6 actual-cell execution
`LogicEngineRuntime.LogicSynthesisExecuting` refines Engine with source-bundle
requests and actual-cell results. `NativeLogicSynthesisEngine` is the lifecycle
actor and also conforms to `LogicSynthesisArtifactLoading`. Request limits are
explicit; library bytes use the sole owned Liberty parser. Saved Verilog is read
back before proof/publishing. `LogicEquivalenceExecuting` schema v3 independently
rechecks a saved synthesis receipt through NativeLogicEquivalenceEngine.

`logic-engine synthesize --request request-v7.json --root ROOT --maximum-request-bytes N` executes the current
pipeline. `verify-mapped --request equivalence-v3.json --root ROOT --maximum-request-bytes N` reopens exact
source/library/netlist/identity/CNF/RUP and reconstructs the proof. Retired metadata
commands no longer exist; old request schemas cannot enter the actual-cell pipeline. Functional evidence does not grant release approval.

Current `synthesize`, `simulate` and `verify-mapped` commands require a positive,
host-addressable `--maximum-request-bytes N`. The caller selects the admission
budget before request JSON is read; oversized or nonregular files fail before
Runtime starts. This limit is independent of cumulative artifact/kernel limits.
Saved parse caps are also bounded by the checked-reload caller's stricter caps.

Current synthesis algorithm v7 / producer 1.5.0 projects aliased ports and binary
constant nets into TimingDesign v2. STA preserves each alias's independent SDC
constraints. A checked all-static setup/hold domain has nil slack with explicit
static checks; missing constraints remain unknown. Saved timing is regenerated
on receipt replay. Earlier algorithms require resynthesis. Required slacks reject unconstrained
coverage even when numeric slacks exist. Native STA evaluates the admitted typed path-exception subset. Excluded timing
checks stay distinct from static and unmeasured checks; every receipt reload repeats
exact-input STA and independently checks actual-cell functional equivalence.

The schema-v7 synthesis request selects `realizationPolicy=standardNetlist` or
`physicalCells`. The host coding value maps to LogicIR's canonical realization
policy. Standard mode preserves binary assignments; physical mode requires exact
inputless tie-cell output instances. Ordinary sequential cells cannot realize
declared binary startup, so synthesis refuses it while source simulation retains
it. Receipt schema4 binds this policy and every checked replay repeats admission.
Missing hold tables remain unmeasured and cannot satisfy a hold requirement.

Source-cell normal-power policies and their complete generated-instance expansion
are owned by [ActualCellExecution](Sources/LogicEngineRuntime/ActualCellExecution/DESIGN.md).
Receipt4 revalidates original Liberty conditions on reload; decoded records and
portable functional proof alone grant no supply or electrical qualification.

An optional explicit `operatingProcessScope` binds exact process, manifest, library,
corner and source operating-condition facts independently of timing measurement.
It expands normal-power conditions without requesting baseline STA. Nil remains
source-only and cannot establish a candidate timing corner. Existing timing inputs
project their exact scope and still execute STA; inconsistent duplicate scopes fail.
The cross-source premise is not a measured or electrically qualified PVT result.

## Retained simulation acceptance

Simulation schema4 accepts an optional exact artifact binding to a schema1
`LogicSimulationSpecification`. Its assertion and binding contract is owned by
[EventExecution](Sources/LogicEngineRuntime/EventExecution/DESIGN.md).
`LogicSimulationResult.assessment` distinguishes unassessed, passed and failed
with retained violations; execution completion alone is not acceptance.
Acceptance schema2/algorithm2 includes Runtime-owned `operationalInputs`; result
provenance inputs exactly match that independently verified closure.
`operationalInputBindings` retains one verified availability per reference in the
same order. The request's
`inputs` remains the immediate selector list. Closure ordering and read scope are
owned by EventExecution. Schema1 acceptance requires a new simulation run.
`LogicSimulationArtifactLoading.load(_:expectedRequest:limits:)` replays saved
acceptance against the caller's exact current request before returning a checked
assessment. `verify-simulation` consumes this requirement through
`LogicSimulationVerificationRequest`; failed or unassessed checks exit nonzero.
