# LogicProof

## Purpose and Scope
Portable synchronous SAT search, independent certificate checking and circuit equivalence.
Parent: [LogicEngine](../../DESIGN.md). Children:
[CNFModel](CNFModel/DESIGN.md), [RUPChecking](RUPChecking/DESIGN.md),
[CDCLSearch](CDCLSearch/DESIGN.md), [CircuitEquivalence](CircuitEquivalence/DESIGN.md).

## Responsibilities and Boundaries
Compose validated CNF/proof values, search, checking and equivalence authority. No filesystem, hash
implementation, JSON, STA, human approval or release policy. Retained structural,
trace and exhaustive host evidence cannot construct a checked RUP proof.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicEngine](../../DESIGN.md) | parent | Product composition | Independent proof product | No new facade |
| [CNFModel](CNFModel/DESIGN.md) | child | Immutable CNF | Literal/clause meaning | Validated publication only |
| [RUPChecking](RUPChecking/DESIGN.md) | child | Checked proof | Independent full-scan propagation | No search watcher reuse |
| [CDCLSearch](CDCLSearch/DESIGN.md) | child | SAT assignment or RUP certificate | Deterministic search | UNSAT status is not checked proof |
| [CircuitEquivalence](CircuitEquivalence/DESIGN.md) | child | Checked inductive verdict | Actual-function miter and replay | Total state correspondence |
| [BinaryRelations](../LogicSimulation/BinaryRelations/DESIGN.md) | depends on | Direct Boolean relation replay | Independent counterexample confirmation | No symbolic helpers |
| [ExecutionControl](../../../../LogicDesign/Sources/LogicKernelCore/ExecutionControl/DESIGN.md) | depends on | Limits/control/typed failure | Cumulative run context | Never reset between stages |

## Architecture
```text
validated formula + structurally validated certificate
    -> independent RUP checking -> checked proof bound to the formula owner
exact circuit pair + correspondence -> miter -> SAT search
    -> certificate checking / independent event replay -> bound equivalence verdict
```

## Contracts and Invariants
Standard Library, portable Core and portable simulation dependencies only. Public designs are immutable
Sendable values, builders noncopyable, spans scoped. Empty CNF is satisfiable;
an empty clause is false. No checked proof is created from a solver status.

## Failure, Concurrency, and Constraints
Invalid values/binding/proof fail explicitly. Resource, cancellation and deadline
errors propagate unchanged. All mutable computation is exclusively run-local.

## Verification and Change Impact
CNF/RUP tests check malformed values, forged steps, missing final contradiction,
wrong formula, valid proofs, limits/control and ownership. Production probes run
on the fixed Native/WASM/Embedded toolchain. Search/equivalence consumers must
verify checked proof binding before publishing equivalence.

| Owner | Native | WASM | Embedded | Access / lifecycle |
|---|---|---|---|---|
| Formula/certificate | Immutable Sendable final storage | Same | Same | Scoped borrows, retained immutable owners |
| Builders | Noncopyable local arrays | Same | Same | Unique mutating access, consuming finish |
| Checker assignments | Run-local Int8 array | Same | Same | Synchronous exclusive scan, release on return/throw |
| Search/encoding/replay | Noncopyable local workspaces | Same | Same | Exclusive synchronous access, scoped scratch release |
| Problem/checked verdict | Immutable Sendable storage | Same | Same | Exact owner binding, no mutable access |

No mutable reference escapes, no target-conditioned conformance or storage, and
no search watcher is shared with the checker. The exhaustive two-variable test
compares checker acceptance to independent truth-table enumeration for all 256
subsets of unit/binary clauses, including learned-unit and tautology prefixes.
