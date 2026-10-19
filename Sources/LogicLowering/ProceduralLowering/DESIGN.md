# ProceduralLowering

## Purpose and Scope
Own resolved procedural RTL to binary word-circuit lowering. Parent:
[LogicLowering](../DESIGN.md). No children. Source parsing/elaboration is a
separate owner; this component accepts the published ResolvedRTL contract.

## Responsibilities and Boundaries
Own ordered blocking environments, delayed NBA writes, branch joins, partial
assignments, combinational completeness, FF and latch state/control conversion.
No source lookup, four-state event execution, technology mapping or proof.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicLowering](../DESIGN.md) | parent | synchronous kernel boundary | portable composition | reuse caller context |
| [ResolvedRTL](../../../../LogicDesign/Sources/LogicIR/ResolvedRTL/DESIGN.md) | depends on | ElaboratedRTL scoped borrows | resolved typed procedural program | publication is not synthesis admission |
| [WordGraph](../../../../LogicDesign/Sources/LogicIR/WordGraph/DESIGN.md) | depends on | WordLogicBuilder publication | binary circuit/control validation | transparent cycles are rejected |
| [BitExpansion](../BitExpansion/DESIGN.md) | used by | WordLogicDesign | next lowering stage | no implicit value sizing |

## Architecture
```text
Immutable RTL spans -> exclusive procedural workspace -> private draft circuit
                      blocking / NBA environments      -> WordLogicBuilder
                      changed-bit branch journals      -> immutable word owner
```

## Contracts and Invariants
LogicWordLowering is a Sendable requirement with typed LogicKernelError, borrowing
ElaboratedRTL and sharing one cumulative inout LogicKernelContext. Every operand
already has resolved width/sign. Constants and retained initial/reset values must
be binary; failures retain the source range where available. Ordinary case uses
first-match priority. Dynamic selections admit only demonstrably in-range offsets;
an out-of-range X result is not replaced by zero.

The procedural environment tracks each signal bit. Blocking writes immediately
affect subsequent reads; NBA writes separately retain data and scheduled-enable.
Final NBA commits override blocking results only on paths that schedule them.
Branches execute from the same baseline and join changed bits; no full environment
copy is taken for each branch. Partial writes cannot introduce a false dependence
on discarded bits of a whole-word old value. Combinational bits must be assigned
on every admitted path. Undriven observed four-state X/Z storage is rejected, including an undriven net;
its source origin is retained. Two-state variables use the ResolvedRTL default 0
for undriven constants and retained state; explicit binary initializers override
the default. Four-state variables retain their unconstrained initial range.
Binary writes are identity under two-state coercion; this does not authorize
silently converting an observed X/Z expression to zero during synthesis. Statement and expression traversal use explicit stacks.

FF/latch bit ordering is signal declaration order then low bit first. All retained
state bits are preserved, with explicit initial range. FF clock/edge come from RTL
controls; synchronous reset/enable may remain explicit next-state logic. Asynchronous
reset requires a dominant polarity-matched branch assigning every retained bit a
binary constant. Its real asynchronous control is retained, never replaced by MUX.
Latch hold is represented by gate control, separate from transparent next data;
explicit feedback is subject to WordGraph transparent-cycle admission. Level-sensitive programs infer latches for incomplete assigned bits and lower
complete bits to their settled binary combinational function. Explicit always_comb
bits require completeness. This does not claim initial-event simulation equivalence. Cross-process
FF blocking read/write races are rejected through selected-bit demand traversal
of final data and controls, including combinational intermediate aliases.

## State, Ownership, and Lifecycle
One noncopyable workspace owns all mutable arrays and one storage receipt. Draft
aliases remain private until resolved and validated; no placeholder escapes as a
published design. Scoped input Spans never escape or cross suspension. The final
builder publishes through consuming finish. There is no shared mutable state;
cancellation uses the existing same-target Mutex owner through checkpoints.

## Failure, Concurrency, and Constraints
Workspace buffers grow only after checked count/byte arithmetic and a replacement
storage reservation. Old and new whole-workspace payload footprints overlap in
the budget during growth (conservative for unchanged arrays); temporary accounting
is released on both success and failure. Published graph/value payload remains
charged for the invocation. These are declared payload capacities, not allocator
metadata/RSS. No allocation or zero-copy performance claim is inferred.

## Verification and Change Impact
LogicWordLoweringTests compares independent binary expected results through the
production RTL->word->bit path: ordered/partial writes, conditional NBA, case
priority/completeness, dynamic selection, FF reset/enable and latch hold/feedback.
Reject X/Z dependencies, incomplete combinational paths, invalid async reset,
unsupported controls and resource/cancellation failures. Shared runtime probes
exercise the public existential on Native, ordinary WASM and Embedded WASM using
the fixed release toolchain/SDK. Frontend composition remains S2 integration-owned.

Assignment groups sample all data and address predicates in the original procedural
environment, retain one dense pre-write expression snapshot, then execute the original ordered
conditional tree with those sampled values. Nested groups share the outer snapshot.
The existing branch journals still own data/enable joins and completeness, and
blocking/NBA effects retain source order. Groups cannot be lowered as ordinary
sequential blocks. The exclusive workspace owns the generation-stamped snapshot
cache on every target; growth and traversal share the invocation storage receipt
and cancellation checkpoints. Failed sampling publishes no candidate.
