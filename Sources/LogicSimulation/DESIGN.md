# LogicSimulation

## Purpose and Scope
Portable four-state functional simulation. Parent: [LogicEngine](../../DESIGN.md).
Children: [CellEvents](CellEvents/DESIGN.md), [RTLEvents](RTLEvents/DESIGN.md),
[BinaryRelations](BinaryRelations/DESIGN.md).

## Responsibilities and Boundaries
Own immutable compiled models, exclusive states and synchronous events. No host
I/O, JSON, STA, delays, proof search or legacy metadata evaluation.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicEngine](../../DESIGN.md) | parent | Portable boundary | Product composition | No host dependency |
| [CellEvents](CellEvents/DESIGN.md) | child | Compile/evaluate requirements | Actual cells and shared model/state API | Bound model/state identity |
| [RTLEvents](RTLEvents/DESIGN.md) | child | RTL admission/events | Procedural four-state execution | Profile and race refusal |
| [BinaryRelations](BinaryRelations/DESIGN.md) | child | Independent two-state relation evaluation | SAT counterexample replay | No CNF or proof search |
| [MappedGraph](../../../LogicDesign/Sources/LogicIR/MappedGraph/DESIGN.md) | depends on | Validated library/netlist | Actual connectivity | Transparent cycles refused |
| [ExecutionControl](../../../LogicDesign/Sources/LogicKernelCore/ExecutionControl/DESIGN.md) | depends on | Typed budgets/control | Cumulative run | Never reset limits |

## Architecture
```text
validated design -> immutable model -> exclusive state + events -> observation
```

## Contracts and Invariants
Standard Library, Core identities, LogicIR and LogicKernelCore only. No original
operation kind substitutes for a mapped library function. Public processing
interfaces are synchronous Sendable requirements with typed kernel errors.

## Verification and Change Impact
LogicSimulationKernelTests and the same Native/WASM/Embedded production probes
own behavior and ownership evidence. The legacy metadata evaluator is retired; these kernels retain their original profile.
