# Optimization Contract Probe

## Purpose and Scope
Parent: [LogicEngine](../../DESIGN.md). No children. Shared Native/WASM/Embedded verification.

## Responsibilities and Boundaries
Independent truth evaluation, origin checks, S4 proofs and S2-to-S6 composition.
Production optimizer/mapper do not depend on this target.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [StateOptimization](../LogicSynthesis/StateOptimization/DESIGN.md) | depends on | LogicOptimizing | Actual candidate path | No performance claim |

## Architecture
```text
fixtures/source -> optimizer -> independent truth and checked proof
```

## Contracts and Invariants
Deterministic fixtures, all small-input assignments, identity interface mapping.
No fake certificate or legacy mapping substitutes for actual execution.

## Verification and Change Impact
LogicOptimizationTests plus both executable probes own behavior evidence.

DeclarationSemanticsContractProbe composes the same source frontend, RTL event
simulation and word/bit lowering requirements. Its source-bound fixtures check
wide mixed X/Z conversion, default and explicit bit initialization, sampled and
partial NBA writes, typed hierarchy/input conversion, net initialization and
undriven Z observation with source-positioned binary-lowering refusal. The Native
test suite invokes separate witnesses; the executable invokes all on each target.

TechnologyMappingContractProbe owns bounded cut, exact actual-function/pin/state matching, counterexample tampering and source-to-mapped induction. The same witnesses run through public existential requirements on all three targets. Host owned-Liberty integration remains in LogicLibraryCompilationTests.
