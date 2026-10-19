# LogicWordLoweringProbeSupport

## Purpose and Scope
Shared portable procedural verification body. Parent:
[LogicEngine](../../DESIGN.md). No children.

## Responsibilities and Boundaries
Exercise public word/bit lowering and interpret the actual emitted gates. This
module is a verification executable dependency, not a production facade.
SourceLoweringContractProbe additionally composes the public frontend with the
production lowering requirements and interprets only emitted bit gates.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Frontend](../../../LogicDesign/Sources/SystemVerilogFrontend/SourceElaboration/DESIGN.md) | depends on | SystemVerilogElaborating | Exact source-to-RTL compilation | Explicit caller profile/capacities |
| [ProceduralLowering](../LogicLowering/ProceduralLowering/DESIGN.md) | depends on | LogicWordLowering | Same production kernel on three targets | Sequential WASI is not race proof |

## Architecture
```text
Native / WASM / Embedded entries -> shared typed probe -> exact source / RTL -> word -> bit
```

## Contracts and Invariants
The same existential call, ordered NBA/blocking and asynchronous reset checks,
initial-state metadata, cancellation and storage refusal execute on all targets.
The source probe checks exact source identities, cumulative composition, actual
8-bit gates, state-preserving next-state relations and refused synthesis input.
Its reference observer takes explicit state and does not simulate event scheduling.
AtomicAssignmentContractProbe additionally checks sampled blocking/NBA swaps
and preserved FF state for all sixteen four-bit patterns. Only the Embedded
entry links its Unicode data library.

## Verification and Change Impact
[Verifier](../../.verification/logic-atomic-lowering/verify-portable.py) records exact
SDK/build/runtime commands and binary identities. Production changes invalidate
source-bound evidence until rebuilt on each claimed target.
