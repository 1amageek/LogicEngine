# LogicEngineCore

## Purpose and Scope
Host execution values. Parent: [LogicEngine](../../DESIGN.md).
Child: [ArtifactStorage](ArtifactStorage/DESIGN.md).

## Responsibilities and Boundaries
Own current host execution errors and exact artifact availability. Portable budgets
and circuit values remain in LogicKernelCore / LogicIR. No actual-cell algorithm,
proof authority or Runtime lifecycle belongs here.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicEngine](../../DESIGN.md) | parent | Host/kernel separation | Composition | Host-only |
| [ArtifactStorage](ArtifactStorage/DESIGN.md) | child | Exact immutable bytes | Acquisition/persistence | No proof inference |

## Architecture
```text
Host execution errors/evidence identity -> injected ArtifactStorage -> digest-verified immutable bytes
```

## Contracts and Invariants
Execution-graph DTOs and their topology/evaluator helpers are removed after all
production and test callers migrate. They have no compatibility decoding path
into validated actual-cell netlists or checked proofs.
Runtime admission and [current capability discovery](../LogicEngine/DESIGN.md)
remain separate from immutable artifact availability.

## Verification and Change Impact
LogicEngineTests own artifact storage and passive evidence behavior. Runtime tests own
actual-cell use. Changes to availability/storage affect both host paths.
