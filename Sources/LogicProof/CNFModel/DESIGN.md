# CNFModel

## Purpose and Scope
Validated CNF storage. Parent: [LogicProof](../DESIGN.md). No children.

## Responsibilities and Boundaries
Own the internal bounded flat-table buffer shared by CNF encoding and search;
its growth reserves old/new overlap and exposes only scoped slices.
Own DIMACS-style signed literal meaning, ordered flat clauses, count/range
invariants and consuming publication. No SAT search or proof acceptance.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicProof](../DESIGN.md) | parent | Portable composition | CNF input owner | No host codec |
| [RUPChecking](../RUPChecking/DESIGN.md) | used by | Literal/clause borrows | Checked propagation input | Immutable complete tables |
| [ExecutionControl](../../../../LogicDesign/Sources/LogicKernelCore/ExecutionControl/DESIGN.md) | depends on | Storage/work/CNF limits | Admission | Explicit capacities |

## Architecture
```text
checked literals -> exclusive fixed-capacity builder -> immutable flat clause owner
                                                     -> scoped clause/literal spans
```

## Contracts and Invariants
Variables are positive one-based dense indices. Literals are nonzero signed
indices; Int.min is invalid. Every literal references a declared variable.
Clauses preserve input order and first occurrence of each literal; duplicate
literals are removed, tautologies retained. Clauses own disjoint consecutive
ranges covering the literal table. Zero variables/clauses and empty clauses are
valid. Display names and hash iteration do not affect meaning.
Builder append failure restores the pre-clause tables; consumed budgets are not
reset. Publication consumes the builder. Immutable storage retains borrow owners.

## State, Ownership, and Lifecycle
Caller selects nonnegative capacities within context limits. Reserve all fixed
payload before allocation, including output storage metadata. Arrays transfer by
immutable ownership; no element-copy or speed claim without measurement.

## Failure, Concurrency, and Constraints
Count/byte arithmetic checked before allocation. Cumulative CNF variables/clauses
and work use the same run context. No shared mutable state or target branches.

## Verification and Change Impact
LogicProofTests owns signed bounds, invalid references, empty/duplicate/tautology
behavior, append failure recovery and consume/borrow compiler refusals. Changes
require RUP and later solver/miter consumer verification.
