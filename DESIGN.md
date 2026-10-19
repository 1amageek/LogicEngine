# LogicEngine Design

## Purpose

Functional logic simulation and logic synthesis over LogicDesign.

## Responsibility boundary

This package owns the schemas and engine protocols listed in its public products. It must remain usable without UI state and without the Xcircuite runtime.

## Non-responsibilities

- Owning canonical RTL or gate IR
- General SystemVerilog/DFT formal solver orchestration
- Physical placement

## Dependency direction

```text
CircuiteFoundation artifact/evidence contract
                 ↓
LogicEngine canonical typed requests/results
                 ↓
native or external-tool backends
                 ↓
Xcircuite composition and stage execution
                 ↓
DesignFlowKernel and .xcircuite artifacts
```

Backends may depend on lower-level data packages. This package must never import
`Xcircuite` or `circuit-studio`. Flow and project storage are supplied by
`DesignFlowKernel` and the injected Xcircuite workspace store; they are not
part of the canonical public contract.

## Trust model

Kernel availability, corpus validation, oracle correlation, process-scoped qualification and release approval are distinct states. The package reports capability and evidence; Xcircuite and ToolQualification apply flow policy.

The legacy metadata lowering, simulation, mapping, bounded-trace and exhaustive
finite-state APIs are retired. Their historical evidence keeps its original scope;
it is not reinterpreted as checked actual-cell RUP evidence. Current public product
and discovery contracts are owned by [LogicEngine](Sources/LogicEngine/DESIGN.md).

## Artifact requirements

All outputs are immutable run artifacts with format, digest, producer metadata and the input design/PDK revision needed to reproduce the result.

## Exact Timing Dependency Adoption

[Package.swift](Package.swift) owns the exact dependency revisions shared with
Xcircuite. This closure adopts verified TimingEngine source contracts, including
[TimingCore strict source characterization](../TimingEngine/Sources/TimingCore/DESIGN.md),
and the verified standard-format dependency closure. It preserves this package's
domain source bytes; it does not claim dependency source or behavior is unchanged.
Manifest inspection checks every exact pin before the composing host resolves,
compiles and exercises the consumed products. Process qualification remains a
separate owner contract.

## Exact PDK Identity Dependency Adoption

[Package.swift](Package.swift) owns the exact revisions consumed by this package.
This adoption consumes the updated PDKCore product directly or transitively.
[Checked PDK identity values](../PDKKit/Sources/PDKCore/Identity/DESIGN.md)
and their immutable schema-2 representation remain owned by the lower contract.
Manifest discovery/exact loading remains owned by
[PDKDiscovery](../PDKKit/Sources/PDKDiscovery/ManifestLoading/DESIGN.md).
Transitive revisions must agree with the composing Xcircuite graph without overrides.
This dependency change preserves this package's domain implementation; lower
behavioral evidence and host identity/provenance tests establish the consumed
contract, not process qualification or unexecuted domain test coverage.

### Checked Transient Dependency Closure

The exact PDK revision in [Package.swift](Package.swift) carries the selected
CoreSpice minimum-step, startup/history and preferred transient-method contract.
LogicEngine has no transient construction or method-selection caller in Sources or
Tests. Its direct PDKCore consumer is the original manifest codec used by
`ActualCellTimingTests`; Runtime consumes the aligned TimingEngine graph for actual
STA and checked receipt reload. Both exact direct pins must agree with that lower
closure before normal resolution. No domain algorithm, numerical tolerance,
artifact schema, or proof authority changes in this adoption.

The focused consuming proof builds the existing host Runtime/test product and
executes `requestedNativeSTAAndObservedConditionSurviveCheckedReload`, including
native synthesis/STA, required-slack refusal, and exact receipt replay. Existing
portable and numerical evidence retains its original scope. Local Git mirrors
provide committed dependency availability; they do not assert upstream publication.

## Portable Kernel Dependency Correction

The approved redesign uses LogicDesign's
[LogicKernelCore](../LogicDesign/Sources/LogicKernelCore/DESIGN.md) for resource
budgets, run control and typed failures. LogicEngineCore must not own a second
context or reset a context between stages. Frontend kernels do not import
LogicEngine. Artifact, filesystem, library acquisition and STA remain host concerns.
Independent checked proof is owned by LogicProof; historical exhaustive or
structural evidence must not be promoted to actual-cell functional proof. Implementation and verification remain tracked in [PROGRESS.md](../PROGRESS.md).

## Verification and Change Impact

The package manifest consumes the [CoreSpice host deployment contract](../CoreSpice/DESIGN.md#responsibilities-and-boundaries) through its exact dependency closure. Changes to that contract require resolution and affected host-product verification.

## Verified Portable IR Adoption

The current dependency adoption consumes exact LogicDesign `9601e43` and its
portable LogicIR / LogicKernelCore products. Host lowering and persisted legacy
execution contracts explicitly import LogicDesignSerialization for codecs and
Codable conformances; they do not move these capabilities back into LogicIR.
Legacy source parsing used by host regression fixtures is imported from LogicDesign,
its actual owner. This historical adoption preserved the then-retained algorithms and API/CLI
behavior. Those legacy products are now retired; current bit-lowering, mapped-cell
and checked-proof contracts have their own evidence. Portable lowering and public source-to-bit composition have independent behavioral
verification; host runtime migration remains tracked in [PROGRESS.md](../PROGRESS.md).

[LogicEngineRuntime](Sources/LogicEngineRuntime/DESIGN.md) owns host library
compilation from TimingCore's original facts. Portable libraries and mapped
netlists remain LogicIR values. Host dependencies stay outside portable targets;
this module adds no Engine facade.

## Typed Lowering Product Migration

[LogicLowering](Sources/LogicLowering/DESIGN.md) is the portable synchronous
kernel product. Current source/cell execution belongs to
[LogicEngineRuntime](Sources/LogicEngineRuntime/DESIGN.md). The old snapshot-to-
execution-graph API and CLI command are removed, without fabricating source,
library or limits from a metadata snapshot. No host re-export enters the portable
product; its independently verified processing contract is unchanged.

[LogicBitLoweringProbeSupport](Sources/LogicBitLoweringProbeSupport/DESIGN.md)
owns the shared three-target verification body. Native/ordinary and Embedded
executable entrypoints differ only in their explicit link dependency.

[LogicWordLoweringProbeSupport](Sources/LogicWordLoweringProbeSupport/DESIGN.md)
owns the shared procedural three-target verification body and explicit executable
entries. The production procedural contract is a child of LogicLowering.
Their executable module contracts are
[Native/ordinary entry](Sources/LogicWordLoweringPortabilityProbe/DESIGN.md) and
[Embedded entry](Sources/LogicWordLoweringEmbeddedPortabilityProbe/DESIGN.md).

The word-lowering verification executables additionally compose the public
SystemVerilogElaborating requirement into word and bit kernels with one cumulative
context. Frontend semantics remain owned by LogicDesign, and production
LogicLowering gains no frontend dependency or new facade. This source profile
requires the existing LogicDesign-qualified 4 MiB debug WASM linear stack and a
4096 KiB Node host stack. These executable-only settings do not alter library
products. Source-to-bit observation is binary functional evidence, not mapped-cell
proof, four-value event simulation or host schema migration.

## Portable four-state simulation

[LogicSimulation](Sources/LogicSimulation/DESIGN.md) owns actual-cell and RTL events and
exclusive model-bound state. The legacy artifact evaluator is removed. Portable kernels
never evaluate metadata mapped parameters. Representation-specific scheduling and
admission are owned by the module children; the public model dispatch retains
validated immutable design ownership.

Four-state event verification targets: [shared body](Sources/LogicSimulationProbeSupport/DESIGN.md),
[Native/WASM entry](Sources/LogicSimulationPortabilityProbe/DESIGN.md),
[Embedded entry](Sources/LogicSimulationEmbeddedPortabilityProbe/DESIGN.md).

## Independent Proof Product

[LogicProof](Sources/LogicProof/DESIGN.md) owns portable CNF and independent RUP
checking. Its child designs own value and proof-authority contracts. Retained host
structural/trace/exhaustive evidence remains distinct and cannot construct a
checked proof. Deterministic CDCL search emits assignments or RUP certificates.
Actual-function circuit equivalence composes independently checked miter proofs
and stabilized original-model replay. Its [owned contract](Sources/LogicProof/CircuitEquivalence/DESIGN.md)
defines initial-state, state correspondence and inconclusive witness boundaries.

Proof verification targets: [shared body](Sources/LogicProofProbeSupport/DESIGN.md),
[Native/WASM entry](Sources/LogicProofPortabilityProbe/DESIGN.md),
[Embedded entry](Sources/LogicProofEmbeddedPortabilityProbe/DESIGN.md).

## Portable Optimization Boundary
[LogicSynthesis](Sources/LogicSynthesis/DESIGN.md) owns two-state candidate
optimization, composed from its validated BitGraph dependency. Caller-owned
[LogicProof](Sources/LogicProof/DESIGN.md) acceptance is separate. Current host execution belongs to Runtime; the legacy metadata mapper is removed.
Metadata mapping is never promoted to functional proof.

[Optimization contract probe](Sources/LogicOptimizationProbeSupport/DESIGN.md) owns shared target verification.

## Resolved Declaration Adoption
[ResolvedRTL](../LogicDesign/Sources/LogicIR/ResolvedRTL/DESIGN.md) owns declared
value-domain/storage/default metadata. [RTL events](Sources/LogicSimulation/RTLEvents/DESIGN.md)
apply it to initialization, input/blocking/NBA writes and dependency admission;
[procedural lowering](Sources/LogicLowering/ProceduralLowering/DESIGN.md) retains
binary initial ranges and refuses observed undriven Z. Neither consumer infers
these properties from WordLogicType's width/sign. The existing portable verification
composition also checks this source-to-consumer boundary.

## Functional Technology Mapping
[TechnologyMapping](Sources/LogicSynthesis/TechnologyMapping/DESIGN.md) owns portable actual-cell candidates, exact physical pins and state-preserving control expansion. Caller-owned LogicProof checks the original bit graph against the actual library-bound netlist. Legacy metadata mapping is retired; current host artifacts belong to Runtime.

## Actual-cell host composition
[Runtime](Sources/LogicEngineRuntime/DESIGN.md) now composes exact source/Liberty,
portable kernels, original-to-actual checked equivalence, required native STA and
immutable artifacts. [Core artifact storage](Sources/LogicEngineCore/DESIGN.md)
owns bounded exact reads. [Public product](Sources/LogicEngine/DESIGN.md) reexports
these contracts directly; [CLI](Sources/LogicEngineCLI/DESIGN.md) selects current
source synthesis, simulation and checked reload without metadata execution.
Consumer adoption is tracked in workspace PROGRESS.md.
[EventExecution](Sources/LogicEngineRuntime/EventExecution/DESIGN.md) owns
retained exact-input four-state specification matching and checked acceptance
replay. Completed simulation, assertion acceptance and release authority remain
separate contracts.

## Actual Realization Contract Adoption

This candidate adopts LogicDesign `8dac4be` startup/constant realization contracts,
Timing `d45fce34` observed hold, actual-cell static functions and versioned STA/SI contracts, and PDK `d827034`
exact profile admission through the root-owned selectors. The current host
composition and portable mapper/proof obligations are owned by
[TechnologyMapping](Sources/LogicSynthesis/TechnologyMapping/DESIGN.md),
[CircuitEquivalence](Sources/LogicProof/CircuitEquivalence/DESIGN.md),
[ActualCellExecution](Sources/LogicEngineRuntime/ActualCellExecution/DESIGN.md) and
[VerifiedArtifacts](Sources/LogicEngineRuntime/VerifiedArtifacts/DESIGN.md).
Earlier adoption sections retain historical evidence scopes, not current pins.

## Cumulative dependency compatibility

The current exact dependency graph is owned by Package.swift; its consuming
compatibility evidence is retained in
[the current run](../.verification/runs/s3-stageIII-20261013-2e1f3af7/s3m-logicengine/completion.json).
This historical compatibility snapshot (`63a4c8b`) preserved production and test
sources from `97173f3`; the later legacy retirement changes only its own scope.
Existing portable mapping, simulation and proof evidence retains its original
scope. Native adoption exercises the existing actual-cell API and real CLI for
source mapping, checked RUP, static physical TIE STA, receipt replay, source startup
observation and refusal of unrealizable startup, unavailable ties and corrupted
proof bytes. Artifact publication and reload preserve request schema5, receipt2,
algorithm5 and producer1.3 authority. This verifies the compiled macOS CPU consumer
path; it does not establish new portable, process or release qualification.

[LogicEvidence](Sources/LogicEvidence/DESIGN.md) owns passive report/oracle
values and has no executable suite or engine dependency.

## Legacy API retirement

The removal is a public compatibility break: three legacy products, six legacy
commands and executable evidence suites no longer exist. Current Runtime source
requests require original source bundles, actual libraries where needed and explicit
limits. Host/RTL callers migrate before obsolete Core graph DTOs are removed.
Passive evidence report/oracle contracts remain available to the Host; they are
not circuit-proof or release authority. [Public discovery](Sources/LogicEngine/DESIGN.md)
owns the single capability field/version contract. Existing current Runtime and
portable source behavior retains its original verification scope.

## Source Distribution Boundary

The root MIT license applies to this package's owned source and documentation,
with explicit owner authorization. Third-party source, dependency licenses,
external tools, model/PDK inputs and their original notices retain their own
terms; this grant does not relicense those materials. Existing source and
resource bytes and any third-party headers remain intact.

This isolated source selection does not establish dependency availability,
execution qualification or process/signoff readiness. Dependency revision
alignment and the consuming public-graph verification are separate gates.

Historical task verification outputs are retained separately from this source
snapshot. Their existing references keep their original finite proof scope;
private task logs and output artifacts are not part of the source distribution.


## Public Prerequisite Dependency Floor

This finite source publication preserves selected implementation/test/resource
bytes from `f5869ffe6ecd518671f6fe90aebb4b529a2ff174`, excluding only the explicitly
selected private `.verification` evidence. It is a prerequisite for Physical's
existing prepared-candidate binding, not a whole-platform release claim. The
public-parent publication has no dependency on private ancestor availability.

| Direct dependency | Exact public source revision | Consumed contract |
|---|---|---|
| CircuiteFoundation | `5f132c58209123433e0e479e1ea61096e46061ba` | Artifact identity, bounded storage and provenance |
| LogicDesign | `5e1d3eec838a0add91c617413682d186a5182335` | Portable IR, shared budgets and source frontend |
| TimingEngine | `be979a9e3095e811f5d7cc4d5f74668142d9c052` | Strict source-selected STA and immutable checked artifacts |
| PDKKit | `f59dfd1dbdd20545ddf97e6a0ab9a956ad7ca809` | Exact process/library profile identity |

`Package.swift` owns these selectors; a fresh canonical public resolution owns the
lock. All transitive revisions must agree without mirrors, edits or local paths.
Historical adoption paragraphs above describe their original snapshots, not this
current dependency selection or an upstream-publication assertion.

The source migration retires old Core graph/document requests and legacy commands;
Runtime and Proof are additional public products. Existing names do not promise
backwards-compatible metadata semantics. Current public processing contracts are
owned by [the product](Sources/LogicEngine/DESIGN.md), with direct host composition
owned by [Runtime](Sources/LogicEngineRuntime/DESIGN.md).

The consuming qualification builds the actual `LogicRuntimeTests` product on the
fresh public graph and executes `OperatingProcessScopeTests` (four cases) and
`ActualCellOperatingConditionTests` (six cases). These check original-source
functional premises, library/corner/PG expansion, actual required STA, candidate
qualification, typed bounds/cancellation and checked persisted reload. They do
not requalify unrelated portable targets, external backends, full temporal
semantics, foundry processes or release policy. No production or test algorithm
changes are part of this dependency/source-publication step.

The r2 public graph resolved eleven clean HTTPS dependencies. On Swift 6.4.0
with the macOS 27 SDK and two build jobs, the explicit `LogicRuntimeTests`
test product compiled in 219.585 seconds. The four `OperatingProcessScopeTests`
and six `ActualCellOperatingConditionTests` all executed with zero skips in
2.145 seconds of test body time (3.025 seconds including the bounded runner).
This includes actual required STA, exact-input replay and fresh candidate
qualification after the original source deadline. No source/test algorithm or
resource limit changed. These focused facts do not qualify other test products,
portable targets, process physics or the whole platform. One source/pin delta
review and explicit publication remain separate gates.

The earlier r1 compile refusal remains retained separately; its old LogicDesign
floor lacked the required mapped/typed-borrow APIs. The current public LogicDesign
preserves those original required source contracts.
