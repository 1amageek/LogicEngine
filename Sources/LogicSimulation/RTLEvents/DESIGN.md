# RTLEvents

## Purpose and Scope
Four-state procedural execution of validated ElaboratedRTL. Parent:
[LogicSimulation](../DESIGN.md). No children. No synthesis or source parsing.

## Responsibilities and Boundaries
Own expression evaluation, process activation, ordered blocking writes, sampled
assignment groups, first-match case and delayed NBA publication. Compile bounded
read/write dependencies and reject driver races and transparent feedback.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicSimulation](../DESIGN.md) | parent | Models/state/events | Same public evaluator | No host dependencies |
| [ResolvedRTL](../../../../LogicDesign/Sources/LogicIR/ResolvedRTL/DESIGN.md) | depends on | Typed spans/processes | Validated input program | Publication is not event admission |
| [LogicValues](../../../../LogicDesign/Sources/LogicIR/LogicValues/DESIGN.md) | depends on | Packed four-state operations | Expression meaning | Z assignment differs from Boolean cell input |

## Architecture
```text
RTL -> bounded process/dependency admission -> immutable model
  -> exclusive run workspace -> atomic inputs -> Active blocking / queued NBA
  -> simultaneous NBA -> reactivation -> stable packed observation
```

## Contracts and Invariants
Preserve specified initial values and obtain unspecified values from each
ResolvedRTL signal's declared default. Initialization and every destination write
follow [ResolvedRTL](../../../../LogicDesign/Sources/LogicIR/ResolvedRTL/DESIGN.md)
value-domain/storage semantics. Input updates, full/partial blocking writes and
sampled NBA data convert to two-state before change detection or queueing.
Unwritten net bits stay Z; variable bits retain their domain-specific default.
Admission value terms apply the same per-bit conversion before ordered reads and
constant branch folding; conversion symbols remain distinct from their four-state
source. Dependency roots conservatively retain source reads. continuous,
always_comb and always_latch processes activate initially; level-sensitive
processes wait for their read sensitivity to change. FF edges use the IEEE
four-state edge table; asynchronous reset assertion activates the process,
release alone does not. Conditions execute their true arm only for logical one;
ordinary case compares all four values exactly and uses first match.
Blocking writes affect later reads in the same process; NBA evaluates data now,
commits selected bits after Active and later NBA wins within one writer.
Assignment groups freeze all expression reads before any writes. Out-of-range or
unknown dynamic reads produce X. Sequential profile, races, completeness and
transparent cycles are admission responsibilities, never resolved by iteration
order. Input events that expose Active-region cross-process blocking hazards are
refused explicitly. Stabilization and all traversals are bounded by run work.

## State, Ownership, and Lifecycle
Immutable plan retains RTL and dense dependency tables. Noncopyable public state
exclusively retains a private non-Sendable run workspace; no mutable workspace
reference escapes the module. Fixed buffers admit their payload before allocation.
Expression generations reuse scratch and preserve immutable values needed by NBA.
Scoped spans never escape or cross await. Failed mutation invalidates the state.

## Failure, Concurrency, and Constraints
Check count products/offsets before storage allocation. Input, output, expression,
process, work and storage limits share the caller's context. Published value
payload is conservatively charged for the invocation, not an allocator/RSS claim.
Unsupported admission is explicit and may not become successful simulation proof.
No shared mutable state, target-conditioned isolation, stream or host callback.

## Verification and Change Impact
RTL event tests own initialization/X/Z, ordered and partial assignments, NBA and
atomic groups, case/condition, edge/reset, latch hold and rejected races/cycles.
Same production probes compile/link/run on Native, WASM and Embedded. CellEvents
regressions protect the shared public model/state/observation contracts.

Admission refinement replaces the process graph with bit-version dependencies.
A run-local dependency arena represents source bits and unions; expression demand
transfer preserves slice/concatenation/extension ranges and ordered blocking
versions. Branch journals retain only changed bit versions, and NBA roots remain
separate from blocking values. Final non-FF roots define transparent topology;
implicit latch hold does not create a transparent self-edge, explicit data feedback
does. Race traversal stops at FF state bits and checks the actual blocking bit.
Growing arena/journal buffers admit old and new payload overlap before allocation.
This closes the independent-output and partial-write counterexamples without a
full signal-table copy per branch. No performance claim is inferred.

Canonical four-state value terms identify control predicates, including ordered
local blocking substitutions. Reduced ordered decision diagrams combine guarded
write coverage across conditionals and first-match case branches. A retained
latch bit must have the same canonical write-enable decision as every other latch
bit; differing canonical gates/polarities are unsupported. This is a qualification
rule, not a proof that differing expressions are functionally unequal. FF/latch
mixing includes inferred level-sensitive state. always_comb requires complete
writes, while level-sensitive procedures may infer state. always_comb/always_latch
sensitivity excludes their written bit expansions, as required by IEEE 1800
9.2.2.2.1; these masks do not replace final-data dependency admission.

Constant control folding uses the same RTLFourStateOperation implementation as
event execution. Only unreachable branches with a proven constant predicate are
pruned. Branch restoration invalidates expression generations before the next
arm. Scalar decisions never merge X/Z with binary don't-care semantics.

| Logical owner | Native | WASM | Embedded | Access / release |
|---|---|---|---|---|
| Model | Immutable Sendable Storage/plan | Same | Same | Borrowed public requirements; ARC retains immutable input |
| Run state | Noncopyable State + exclusive RTLEventWorkspace | Same | Same | Unique inout evaluate; no workspace reference escapes |
| Admission | Noncopyable dependency/guard workspace | Same | Same | Synchronous run-local mutation; scratch receipts released |

The shared source has no target-conditioned storage, conformance or isolation.
Native task-group tests share only the immutable model, creating eight independent
states. WASI runtime tests are sequential and make no parallel-safety claim.
