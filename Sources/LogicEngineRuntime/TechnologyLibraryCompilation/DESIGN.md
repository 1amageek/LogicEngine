# TechnologyLibraryCompilation

## Purpose and Scope

Compile owned Liberty facts to a portable library and immutable eligibility report.
Parent: [LogicEngineRuntime](../DESIGN.md). No children.

## Responsibilities and Boundaries

Verify exact SHA-256 source identity; bind names to physical input/state slots;
expand inverted state references; admit the explicit single-state-cell profile.
Own no parser, timing/power inference, cross-view qualification, mapper or proof.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicEngineRuntime](../DESIGN.md) | parent | Host ownership | Library preparation | No artifact publication |
| [LibertyCodec](../../../../TimingEngine/Sources/TimingCore/LibertyCodec/DESIGN.md) | depends on | Original positioned facts | Sole grammar owner | Preserve unsupported semantics |
| [TechnologyLibrary](../../../../LogicDesign/Sources/LogicIR/TechnologyLibrary/DESIGN.md) | depends on | Consuming validated builders | Actual pin/state namespace | No approximation |
| [ExecutionControl](../../../../LogicDesign/Sources/LogicKernelCore/ExecutionControl/DESIGN.md) | depends on | Cumulative budgets/control | Admission | No context reset |

## Architecture

```text
owned source + expected ArtifactID + explicit ID base + context
  -> exact hash -> eligibility -> named-slot rebinding -> consuming builders
  -> library? + every original cell's positioned outcome
```

## Contracts and Invariants

`LogicTechnologyLibraryCompiling` is a synchronous Sendable processing protocol.
Input is OwnedLibertySource, expected SHA-256 identity, explicit identity-base
options and the caller's inout context. Byte count/digest are checked against the
actual original bytes. Source mismatch/hash failure publishes no compilation.
The codec's live-storage accounting remains caller-owned; compilation admits all
storage/work it creates. IDs use checked source-order prefix counts from a nonzero
base, including rejected cells; dense indices include only admitted cells.
Duplicate source cell names fail. Identical bytes/options give identical results.

Admission requires explicit finite nonnegative area, ordinary input/output pins,
an output and actual normalized functions for every output. dont_use true excludes
a cell. Missing area/functions, unsupported directions/groups, banks, state tables,
memories, bundles, bus pins, tri-state, x_function and state_function receive reasons.
No power, timing, layout/SPICE compatibility or cross-view binding is inferred.

A sequential cell has one FF/latch group and two distinct state symbols disjoint
from all pins. First is Q; second becomes explicit inversion of Q. Data functions
may encode feedback, synchronous reset and enable. Clock/gate and optional single
clear/preset must be physical input literals with inversion parity defining their
polarity. Clear resets to zero; preset to one. Additional/compound controls,
simultaneous clear/preset and unbound symbols are ineligible.
Asynchronous reset is never converted to a data MUX.

### Source normal-power premises

Schema-6 compilation consumes TimingCore's source-owned normal-power validator.
PG-declared or pin/group power-down cells require explicit source-cell conditions;
unconditional compilation excludes them. No PG type/value or power-down Boolean
interpretation is duplicated here. The lower owner requires every declared PG pin
exactly once with its original type/value and proves every power-down program false
for all binary data/current-state values. Logic supplies no signal/state constants.
Resource/deadline/cancellation failure aborts instead of becoming ineligibility.
Existing `dont_use` and unsupported-functional-group exclusions remain positioned
cell outcomes; those cells never become candidates. Explicit policies for them
still pass through the source validator, including unused policies.
The synchronous lower admission hook charges the existing cumulative Logic context.

Conditional compilation preserves original functions, signal pins, state/control
binding and unknown startup. The portable library is a declared functional model
under retained host premises; mathematical proof alone grants no normal-power or
electrical qualification. Retain checked lower outcomes; decode grants no authority.
[ActualCellExecution](../ActualCellExecution/DESIGN.md) owns policy/instance binding;
[VerifiedArtifacts](../VerifiedArtifacts/DESIGN.md) owns exact-source replay.

Rebuild every function through the Boolean builder with the full pin/state
namespace. Refuse input-pin functions and physical-output references. Preserve
actual operators/edges; never infer gate kind. A nil library with explicit outcomes
means no library candidate, not successful synthesis or an empty usable library.

The legacy JSON metadata profile cannot represent Liberty functions. Remove its
duplicate interpreter and explicitly refuse Liberty pending actual mapped-runtime
migration. JSON decoding failures never fall through to another grammar. Retained
metadata mapping is not functional proof.

## State, Ownership, and Lifecycle

Compiler is a Sendable value with injected ContentDigesting. Construction is local;
results share immutable final storage with scoped eligibility borrows. Retain the
input owner throughout compilation. No shared mutable state, stream or shutdown.

## Failure, Concurrency, and Constraints

Kernel, digest, artifact-ID and identity-mismatch failures are distinct typed cases.
Release temporary hash storage on success/failure, preserving a primary failure if
cleanup fails. The digest API borrows Array: make one admitted exact-byte copy at
this host API boundary and charge copy/hash work. Check control before and after
opaque digest work; storage/work admission bounds input size. This is not zero-copy.
Check capacities and ID arithmetic before allocation. Symbol/remapping payload is
conservatively charged for the invocation, matching portable builder admission.
Allocator metadata, opaque crypto overhead and RSS are outside payload accounting.
Resource/cancel/deadline failure aborts compilation, never cell ineligibility.

Normal-power validation always uses the source owner's retained parse accountant.
Its synchronous admission hook reports work, workspace slots and exact new source
reservation bytes before allocation. Logic charges slots to `nodes` separately
from bytes. Runtime parsing has already conservatively reserved its peak in the
shared context; only `parsePeak - currentSourceBytes` is initial byte credit.
Each new source reservation consumes this credit once, reserves any additional
bytes in the same context, and charges allocation bytes for the reused portion.
Source releases do not replenish credit. Thus the context retains a conservative
invocation envelope while the source accountant owns actual live/temporary
reservations and their release. Standalone compilation has zero credit. Neither
workspace slots nor allocator/RSS estimates substitute for exact source bytes.

## Verification and Change Impact

LogicLibraryCompilationTests own source -> compiler -> actual cell/netlist checks
with independent truth functions, NAND/NOR/pin permutations, constants/multiple
outputs, Q/QN, enable/reset/latch, power-down refusal, absent/bad functions,
dont_use, area, forged identity, all-ineligible reports, IDs and resource/control
failures. SynthesisTests own explicit legacy Liberty refusal and JSON error behavior.
Native host API/CLI checks verify adoption. Events, symbolic proof and PDK/STA
integration remain subsequent consumer-owned gates.
