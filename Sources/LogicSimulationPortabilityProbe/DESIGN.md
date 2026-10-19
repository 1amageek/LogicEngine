# LogicSimulationPortabilityProbe

## Purpose and Scope
Portable actual-cell and RTL event verification. Parent: [LogicEngine](../../DESIGN.md).
No children. This is a verification target, not a production facade.

## Responsibilities and Boundaries
Invoke the public production compiler/evaluator with the same fixtures on all
three targets. Own no alternative simulation implementation.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicEngine](../../DESIGN.md) | parent | Verification composition | Target ownership | No qualification claim |
| [CellEvents](../LogicSimulation/CellEvents/DESIGN.md) | depends on | Simulation requirements | Production behavior | Sequential WASI is not parallel safety |

## Architecture
```text
Native / WASM / Embedded -> shared fixture -> production event kernel -> assertions
```

## Contracts and Invariants
Run the [shared production fixtures](../LogicSimulationProbeSupport/DESIGN.md).
They own the behavioral assertions for actual cells and RTL.
Only the Embedded executable links Unicode tables. Fixed release SDKs match the
compiler; input/model/state contracts remain identical.

## Verification and Change Impact
.verification/logic-rtl-events records build/link/runtime commands and binary
identities. Native LogicSimulationKernelTests cover negative event/lifecycle paths.
