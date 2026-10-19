# RUPChecking

## Purpose and Scope
Independent reverse unit propagation verification. Parent:
[LogicProof](../DESIGN.md). No children.

## Responsibilities and Boundaries
Own immutable ordered RUP certificates, formula binding and checked proof
construction. Own full-clause-scan unit propagation. No SAT search, watchers,
preprocessing, clause deletion, approval or trust promotion.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicProof](../DESIGN.md) | parent | Proof boundary | Checked authority | Status alone is insufficient |
| [CNFModel](../CNFModel/DESIGN.md) | depends on | Validated literal/range spans | Original formula | Exact structural binding |
| [ExecutionControl](../../../../LogicDesign/Sources/LogicKernelCore/ExecutionControl/DESIGN.md) | depends on | Budgets/control | Bounded independent computation | Release scratch on failure |

## Architecture
```text
formula + bound certificate -> compare actual CNF content
    -> negate each added clause -> full-scan unit propagation
    -> contradiction using formula + previously checked clauses
    -> final empty clause -> private checked-proof construction
```

## Contracts and Invariants
A certificate retains the immutable formula it covers and structurally validated
clause tables. It must terminate with exactly one final empty clause. Structural
validation is not proof acceptance. Each addition must be RUP before later steps
may use it. Missing/invalid steps cannot become a checked proof. Exact CNF content
must match; evidence for another formula is rejected before proof traversal.
The checked receipt binds the formula argument's immutable owner, so a processing
boundary can reject a receipt returned for another input. Its initializer is
private; the only construction path performs independent checking.

## Runtime Flows
For each clause, clear assignments, assume each literal false, propagate original
and previously verified clauses until conflict or fixpoint. Conflicting assumptions
make a tautology RUP. A fixpoint without conflict rejects the addition. The final
empty addition proves UNSAT. No search data or watcher state is accepted.

## State, Ownership, and Lifecycle
Noncopyable fixed-capacity certificate builder. Run-local Int8 assignments,
released on success/throw. Formula/certificate/checked result are immutable
Sendable values. All targets use the same storage/access implementation.

## Failure, Concurrency, and Constraints
Proof budget counts fixed-width logical header/length/literal payload; host JSON
bytes are separately bounded by its codec. All arithmetic, storage and per-scan
work are checked. Cancellation/deadline/resources propagate; no receipt escapes
partial checking. Different canonical CNF content is invalid binding, regardless
of whether another contradiction could be proved.

## Verification and Change Impact
LogicProofTests covers true/false RUP, learned clauses, duplicate/tautological
literals, missing contradiction, altered formula, control/resource failures and
compiler refusal of external receipt construction. Native/WASM/Embedded probes
invoke the public requirement through an existential. Later SAT/equivalence
components must keep their search and replay implementations independent.
