# LogicSimulationProbeSupport

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
| [RTLEvents](../LogicSimulation/RTLEvents/DESIGN.md) | depends on | RTL compilation/events | Source semantic verification | Same production evaluator |

## Architecture
```text
Native / WASM / Embedded -> shared fixture -> production event kernel -> assertions
```

## Contracts and Invariants
Run real NAND truth, FF simultaneous capture/reset release, latch transparency,
source RTL NBA sampling, independent process outputs and canonical latch gates.
Only the Embedded executable links Unicode tables. Fixed release SDKs match the
compiler; input/model/state contracts remain identical.

## Verification and Change Impact
.verification/logic-cell-events records build/link/runtime commands and binary
identities. Native LogicSimulationKernelTests cover negative event/lifecycle paths.
