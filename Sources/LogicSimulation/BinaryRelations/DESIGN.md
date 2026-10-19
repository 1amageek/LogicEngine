# BinaryRelations

## Purpose and Scope
Independent two-state evaluation of combinational observation and state update
relations. Parent: [LogicSimulation](../DESIGN.md). No children.

## Responsibilities and Boundaries
Evaluate original bit operations or actual mapped cell functions directly. Own
no CNF, SAT search or proof acceptance. This relation evaluator complements the
four-state event simulator; it does not claim four-state equivalence.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicSimulation](../DESIGN.md) | parent | Synchronous evaluation | Relation replay | Separate from event scheduling |
| [BitGraph](../../../../LogicDesign/Sources/LogicIR/BitGraph/DESIGN.md) | depends on | Validated graph/state | Neutral functions | State is an independent cut point |
| [MappedGraph](../../../../LogicDesign/Sources/LogicIR/MappedGraph/DESIGN.md) | depends on | Actual cell/pin functions | Mapped functions | Never infer from original opcode |
| [CircuitEquivalence](../../LogicProof/CircuitEquivalence/DESIGN.md) | used by | Replay of SAT assignment | Independent counterexample confirmation | No symbolic workspace reuse |

## Architecture
```text
input bits + current state bits -> direct Boolean evaluation
    -> output bits + per-state control / sampled update / asynchronous update
```

## Contracts and Invariants
Inputs and outputs flatten ports in declaration order, each port in stored bit
order. Bit state order is its state table; mapped state order is sequential
instances in instance-table order. State cuts use the supplied current value.
FF sampled updates apply enable then reset priority; asynchronous updates apply
only asynchronous reset, otherwise retain Q. FF control retains clock and edge.
Latch control is normalized active gate, sampled update is gate ? D : Q with
reset priority. Its asynchronous update applies reset only. Comparing these
relations for all inputs/current states is sufficient to preserve event updates
and noncyclic transparent stabilization, without treating a finite trace as proof.
The scalar initial-event API accepts a common raw physical previous-control value and supplied
initial Q values, applies simultaneous FF updates/asynchronous reset and iterates
latch/derived-control propagation to stability. It reuses one exclusive workspace;
only the final output/state observation is published. Nonstabilizing execution
exhausts the caller work budget rather than returning a partial observation.

## State, Ownership, and Lifecycle
Immutable Sendable observation owns output/action tables. Noncopyable run-local
workspace owns signals, function scratch and instance/state correspondence.
Scoped spans do not escape. All targets have the same storage/access contracts.

## Failure, Concurrency, and Constraints
Dimension errors fail explicitly. Checked reservations cover scratch and published
outputs; work and output budgets are cumulative. Cancel/deadline/resource failures
propagate. No mutable reference escapes and no target synchronization branch exists.

## Verification and Change Impact
Circuit equivalence tests compare replay to enumerated truth and four-state event
fixtures restricted to binary values. Wrong mapped function/pin/reset/edge must
produce a confirmed difference. Changes require symbolic/replay differential tests.

## Explicit Physical Event History

The `LogicBinaryEvaluating.replayInitialEvent(...previousControls:context:)`
requirement accepts exactly one previous physical clock-pin value per native state
ordinal. The scalar overload keeps its existing common physical value semantics;
it is not reinterpreted as a logical-root clock. The explicit vector is borrowed,
validated before allocation, then copied once into the already budgeted exclusive
workspace. Each FF evaluates its actual local edge and actual cell control value.
Latch behavior remains level-sensitive and does not consume clock history.

```text
caller physical histories -> dimension/control admission -> exclusive workspace
                         -> actual cell/pin evaluation -> simultaneous updates
                         -> stabilization -> immutable observation
```

Both overloads share the same event execution body, quota, cancellation and release
paths. There is no root-clock collapsing or symbolic helper reuse in this evaluator.
LogicProof owns translating a validated lineage into physical histories. A protocol
existential calls the declared vector requirement on Native, WASM and Embedded.
