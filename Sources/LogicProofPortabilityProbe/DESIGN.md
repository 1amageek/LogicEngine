# LogicProofPortabilityProbe

## Purpose and Scope
Production proof verification target. Parent: [LogicEngine](../../DESIGN.md).
No children. No alternative checker implementation.

## Responsibilities and Boundaries
Compose the public CNF/certificate builders and independent checker with fixed
valid/forged fixtures. The support target owns assertions; executable entrypoints
invoke the shared body.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicEngine](../../DESIGN.md) | parent | Verification composition | Product evidence | No release qualification |
| [LogicProof](../LogicProof/DESIGN.md) | depends on | Validated CNF/RUP and checked proof | Production behavior | No solver status accepted |

## Architecture
```text
Native / WASM / Embedded entry -> shared fixtures -> production checker
```

## Contracts and Invariants
Valid unit and learned-clause contradictions pass; forged satisfiable proofs fail.
Protocol existential invokes declared requirements. All targets use identical
public value and error contracts. Only Embedded links Unicode tables.

## Verification and Change Impact
.verification/logic-rup-checking records exact source/binary identities and
compile/link/runtime. LogicProofTests owns negative/control cases. Sequential
WASI execution does not establish thread concurrency or performance.
