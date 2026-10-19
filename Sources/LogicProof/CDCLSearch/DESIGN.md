# CDCLSearch

## Purpose and Scope
Deterministic synchronous SAT search. Parent: [LogicProof](../DESIGN.md).
No children. Owns the native solver, portable on the fixed three targets.

## Responsibilities and Boundaries
Search CNF using two watched literals and first unique implication point learning.
Return a satisfying assignment or a bound RUP certificate. Independent proof
acceptance belongs to RUPChecking; circuit replay belongs to later equivalence.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicProof](../DESIGN.md) | parent | Portable proof composition | Search boundary | No checked receipt authority |
| [CNFModel](../CNFModel/DESIGN.md) | depends on | Validated CNF | Immutable source clauses | Literal indices are one based |
| [RUPChecking](../RUPChecking/DESIGN.md) | depends on | Certificate builder | Ordered learned clauses plus final empty clause | No checker workspace reuse |
| [ExecutionControl](../../../../LogicDesign/Sources/LogicKernelCore/ExecutionControl/DESIGN.md) | depends on | Budgets/control | Cumulative accounting | Growth accounts for old/new overlap |

## Architecture
```text
CNF -> exclusive search workspace -> watched propagation
    -> conflict -> 1-UIP resolution -> backjump -> asserting clause
    -> total assignment / learned RUP steps + empty contradiction
```

## Contracts and Invariants
Choose the first unassigned variable in ascending order, false first. Clause and
watch traversal order are stable. No preprocessing, restart, clause minimization
or deletion. Each non-unit clause has two distinct watched positions; a unit has
one. Conflict analysis resolves reasons until exactly one current-level literal
remains. Backjump to the greatest other level and enqueue the asserting literal.
Every learned clause is retained in insertion order for the certificate.
SAT output is total and checked against every original clause before publication.
UNSAT output requires the final empty clause, but is not an equivalence verdict.

## State, Ownership, and Lifecycle
Noncopyable workspace owns assignments, levels, reasons, trail, analysis scratch,
flat clauses and linked watch records. Public output is immutable Sendable.
Dynamic buffers reserve replacement storage while retaining the old reservation,
then release the old reservation. Workspace storage releases on return or throw;
published assignment/certificate storage remains accounted to the run context.
All targets have identical storage and access contracts, with no shared mutation.

## Failure, Concurrency, and Constraints
Checked index/capacity arithmetic precedes allocation. Work, search steps, learned
CNF clauses, proof payload, output and storage are bounded by the caller context.
Cancellation, deadline and resource errors propagate without a success outcome.
No guessed search size or platform fallback is introduced.

## Verification and Change Impact
LogicProofTests compares SAT status and assignments to independent enumeration,
checks every UNSAT certificate with the full-scan checker, exercises non-root
learning/backjumps, relocation, tautologies, empty clauses, determinism and failure.
Production probes run the public existential on Native/WASM/Embedded. Changes to
CNF, learning or certificate order require rerunning both search and checker tests.
