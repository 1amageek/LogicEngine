# LogicProofProbeSupport

## Purpose and Scope
Production proof verification target. Parent: [LogicEngine](../../DESIGN.md).
No children. No alternative checker implementation.

## Responsibilities and Boundaries
Compose the public CNF/certificate builders, CDCL solver and independent checker
with fixed valid/forged fixtures. The support target owns assertions; executable entrypoints
invoke the shared body.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicEngine](../../DESIGN.md) | parent | Verification composition | Product evidence | No release qualification |
| [LogicProof](../LogicProof/DESIGN.md) | depends on | Validated CNF/RUP and checked proof | Production behavior | No solver status accepted |

## Architecture
```text
Native / WASM / Embedded entry -> shared fixtures -> CDCL -> production checker
```

## Contracts and Invariants
Valid unit and learned-clause contradictions pass; forged satisfiable proofs fail.
Search produces a satisfying assignment or independently checked RUP contradiction.
Equivalence fixtures construct validated bit graphs and actual-cell netlists,
requiring a bound checked proof or a stabilized replay-confirmed counterexample.
Protocol existential invokes declared requirements. All targets use identical
public value and error contracts. Only Embedded links Unicode tables.

## Verification and Change Impact
.verification/logic-rup-checking and .verification/logic-cdcl-search record exact source/binary identities and
compile/link/runtime. LogicProofTests owns negative/control cases. Sequential
WASI execution does not establish thread concurrency or performance.


The clock-lineage probe composes actual cell graphs, proof/recheck and explicit
physical-history event replay on all three targets. Its root 0-to-1, D=1, Q=0 oracle
requires direct rising and inverted falling cells to capture, while inverted rising
cells hold. Mixed parity uses separate actual pin histories. This does not establish
CTS delay, PEX, STA, DRC/LVS, physical qualification or Host release eligibility.
