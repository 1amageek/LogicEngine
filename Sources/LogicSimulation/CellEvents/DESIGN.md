# CellEvents

## Purpose and Scope
Actual-cell zero-delay functional events. Parent: [LogicSimulation](../DESIGN.md).
No children. No analog/SDF delay or timing signoff.

## Responsibilities and Boundaries
Compile exact mapped/library pairs; execute physical pin functions and one-bit
state definitions. Own the common public model/state/event requirements and
dispatch RTL execution to RTLEvents. Own mapped run-local arrays, event ordering
and invalidation on failure.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicSimulation](../DESIGN.md) | parent | Portable kernels | Simulation owner | No host services |
| [RTLEvents](../RTLEvents/DESIGN.md) | coordinates with | RTL model admission/execution | Shared public event boundary | Distinct scheduling and Z meaning |
| [MappedGraph](../../../../LogicDesign/Sources/LogicIR/MappedGraph/DESIGN.md) | depends on | Topology/library identity | Trusted validated graph | No re-inference |
| [TechnologyLibrary](../../../../LogicDesign/Sources/LogicIR/TechnologyLibrary/DESIGN.md) | depends on | Boolean/state functions | Cell meaning | Explicit functional extension |

## Architecture
```text
exact library check -> immutable model
  -> makeState(X or specified Q) -> atomic input event -> settle old state
  -> sample all FF -> simultaneous state commit -> settle -> observation
```

## Contracts and Invariants
Events update complete input ports simultaneously and carry nondecreasing logical
time. Reject duplicate ports, output writes, width mismatch and cross-model state.
Inputs and unspecified state start X. Events use dense indices, never display names.
Combinational values follow actual Boolean functions: each Boolean input Z becomes
X; constants and ordinary four-state truth operations then determine outputs. This
is the declared conservative functional Liberty extension, not RTL wire assignment.
FF edges include 0->X/Z and X/Z->1 for rising, and the dual for falling; X<->Z is
not an edge. Every FF samples the same pre-NBA values. Reset has priority: known
active reset forces the defined value; unknown reset merges reset/otherwise result.
Reset release alone holds FF state. Latch gate active copies data, inactive holds;
unknown gate merges data/hold. The mapped validator refuses transparent cycles and
mixed/split sequential profiles. Derived clock events after state publication are
processed in subsequent delta cycles, charged to the same work budget.

## State, Ownership, and Lifecycle
Model shares immutable final storage. State is noncopyable and bound by retained
model owner identity. Fixed arrays are admitted before allocation; function scratch
is reused in every evaluation. Scoped borrows never escape or cross await. State
is invalidated before mutation, restored only after complete observation; a failed
run cannot be resumed as successful. New state is the explicit restart boundary.
Observation owns immutable packed values. No shared mutable state or shutdown.

## Failure, Concurrency, and Constraints
All capacity arithmetic checked before allocation. Cumulative managed payload,
work, outputs and control checkpoints bound events/delta iterations. Published
observation payload remains charged for the invocation. Allocator overhead/RSS
are not claimed. No zero-copy speed claim without measurement. Native/WASI
sequential execution does not prove real thread concurrency.

## Verification and Change Impact
LogicSimulationKernelTests verify NAND/pin polarity, initial X/Z, FF simultaneous
sampling, edge/reset release, enable feedback, transparent hold/cycle refusal,
wrong library/state/event, limits and cancellation. Shared production probes run
on three fixed targets; compiler-negative tests enforce noncopyable state/borrows.
RTL event scheduling and binary proof replay are separate consumer contracts.
