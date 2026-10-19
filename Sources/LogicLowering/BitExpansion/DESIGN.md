# BitExpansion

## Purpose and Scope
Expand validated resolved word operations into binary bit circuits. Parent:
[LogicLowering](../DESIGN.md). No children.

## Responsibilities and Boundaries
Own arithmetic, bitwise, comparison, logical, reduction, selection, concatenation,
slice, extension and shift expansion. Preserve every state bit and its controls.
Frontend expression sizing, four-state simulation, optimization and technology
mapping remain outside this component.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Portable processing boundary | Composition | Synchronous only |
| [WordGraph](../../../../LogicDesign/Sources/LogicIR/WordGraph/DESIGN.md) | depends on | Width/sign and operation invariants | Semantic input authority | Arithmetic is modulo width |
| [BitGraph](../../../../LogicDesign/Sources/LogicIR/BitGraph/DESIGN.md) | depends on | Builder and validated topology | Output publication | Single FF or latch profile |

## Architecture
```text
borrow word tables -> checked capacity plan -> exclusive workspace/builder
    -> connectivity order -> bit operations -> state/port expansion -> validate
```

## Contracts and Invariants
All permitted binary inputs and initial states preserve word results and next
state. WordGraph publication already rejects constants, explicit initial values
and reset values containing X/Z; lowering relies on that checked immutable
guarantee and never substitutes binary defaults.
Unspecified initial values remain unspecified. Signed arithmetic is modular;
ordering uses operand signedness. Arithmetic right shift sign-fills only a signed
left operand, including shift amounts wider than a native integer. First concat
operand is most significant. State bit order is word-state order then low bit
first. Reset kind/polarity/value, clock edge, enable and latch gate are retained.
Each generated node/state copies its source origin. Generated entity IDs are
deterministic local identities, separate from dense indices; port IDs are retained.
Alias operations emit buffers to preserve their own origin. No name/ID sort defines
evaluation order. Publication runs the shared bit validator.

## State, Ownership, and Lifecycle
Input tables are scoped Span borrows; no view escapes or crosses await. A noncopyable
workspace owns contiguous bit bindings, offsets, shift buffers and reusable operand/
port buffers. Published builder storage stays charged to the invocation, including
on failed construction; temporary workspace reservation is released on all paths.
Managed bytes measure declared payload capacities, not allocator metadata or RSS.
There is no shared mutable state or target-specific synchronization branch.

## Failure, Concurrency, and Constraints
Capacity products/sums and byte counts are checked before allocation. The caller's
cumulative expansion, nodes, edges, states, work and storage limits and run control
remain active throughout. Capacity estimates may conservatively reject a candidate.
Cancellation/deadline/limits propagate as typed errors; no partial design is returned.

## Verification and Change Impact
[Tests](../../../Tests/LogicBitLoweringTests) independently compare small-width
full binary domains, wide carries/shifts, controls, topology/origins and typed
failures. Three-target runtime probes check the same kernel and existential
requirement. Functional claims apply to this transformation, not mapped circuits
or frontend acceptance. Changed word or bit contracts require these tests.
