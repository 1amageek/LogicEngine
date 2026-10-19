# LogicEngine product

## Purpose and Scope
Public reexports and capability discovery. Parent: [Package](../../DESIGN.md).
No children.

## Responsibilities and Boundaries
Expose Runtime and portable kernel products directly. Own no combined execution
protocol, wrapper engine, alternate semantics or trust/release decision.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Composition | Public product | No new facade |
| [Runtime](../LogicEngineRuntime/DESIGN.md) | depends on | Actual-cell host engines | Default API | Capability schema is independently versioned |

## Architecture
```text
LogicEngine -> Runtime + lowering/simulation/synthesis/proof requirements
```

## Contracts and Invariants
Default source synthesis emits actual physical cells and checked proof receipts.
Capability schema 3 describes only the current public processing contracts. Schema 2
and earlier are rejected on decode. Legacy metadata execution, bounded traces,
finite-state exhaustive equivalence and suite execution APIs are retired; checked
RUP does not replace their four-state temporal contract.

| Capability | Current guarantee | Version source |
|---|---|---|
| Lowering | Typed word/bit kernels; binary synthesis admission | Portable kernel contracts |
| Simulation | Four-state source/actual-cell events and exact retained assertion acceptance/replay | `LogicSimulationRequest.currentSchemaVersion` |
| Synthesis | Actual physical-cell mapping, independent RUP checking and checked reload | `LogicSynthesisRequest.currentSchemaVersion` |
| Equivalence | Checked actual-cell functional proof and exact artifact reload | `LogicEquivalenceRequest.currentSchemaVersion` |
| Evidence | Passive report validation and independent oracle correlation | Report schema remains 1 |

Request version fields use the exact UInt16 type of SchemaVersion.major.
Discovery does not grant process qualification or release authority. It advertises
no retired metadata command, trace/exhaustive engine or executable evidence suite.

## Verification and Change Impact
API/CLI tests own public product resolution and distinct schema admission.
