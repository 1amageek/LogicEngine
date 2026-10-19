# LogicSynthesis

## Purpose and Scope
Portable two-state, state-preserving optimization and functional technology mapping. Parent: [LogicEngine](../../DESIGN.md).
Children: [StateOptimization](StateOptimization/DESIGN.md), [TechnologyMapping](TechnologyMapping/DESIGN.md).

## Responsibilities and Boundaries
Generate unverified optimization and actual-cell mapping candidates. No proof acceptance, file I/O,
serialization, STA or host library preparation.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicEngine](../../DESIGN.md) | parent | Composition | Public product | Current host execution belongs to Runtime |
| [StateOptimization](StateOptimization/DESIGN.md) | child | LogicOptimizing | Canonicalization and provenance | Two-state only |
| [TechnologyMapping](TechnologyMapping/DESIGN.md) | child | LogicTechnologyMapping | Exact actual-cell candidates | Caller proves equivalence |
| [BitGraph](../../../LogicDesign/Sources/LogicIR/BitGraph/DESIGN.md) | depends on | Validated immutable graph | Values and topology | Preserve state and ports |
| [ExecutionControl](../../../LogicDesign/Sources/LogicKernelCore/ExecutionControl/DESIGN.md) | depends on | Cumulative budget | Synchronous control | No reset |
| [LogicProof](../LogicProof/DESIGN.md) | coordinates with | Equivalence check | Caller verifies candidates | No dependency on proof search |

## Architecture
```text
validated bit graph -> exclusive workspace -> validated candidate
                                            -> caller-owned proof check
```

## Contracts and Invariants
Standard Library, CircuiteFoundation Core, LogicIR and LogicKernelCore only.
Sendable immutable public values; noncopyable run-local workspace. All processing
operations are typed-throwing protocol requirements.

## Verification and Change Impact
LogicOptimizationTests and production three-target probes own candidate behavior.
The legacy metadata mapper is retired. Actual-cell mapping is owned by
TechnologyMapping; [Runtime](../LogicEngineRuntime/DESIGN.md) owns current source execution.
