# StateOptimization

## Purpose and Scope
Parent: [LogicSynthesis](../DESIGN.md). Own canonical Boolean optimization and
source-node correspondence. No children.

## Responsibilities and Boundaries
Constant propagation, buffer/double-negation elimination, commutative structural
hashing, Boolean identities and unreachable logic removal. Preserve every input
and state bit, port order, initial range, state control and source identity.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicSynthesis](../DESIGN.md) | parent | Portable processing | Module composition | Candidate is unverified |
| [BitGraph](../../../../LogicDesign/Sources/LogicIR/BitGraph/DESIGN.md) | depends on | Builder and topology | Validation before publication | No identifier sorting |
| [CircuitEquivalence](../../LogicProof/CircuitEquivalence/DESIGN.md) | coordinates with | Checked equivalence | Consumer acceptance | Two-state proof only |

## Architecture
```text
connection topology -> canonical nodes -> live roots -> validated rebuild
                           |                              |
source-node map -----------+------------------------------+-> origin correspondence
```

## Contracts and Invariants
`LogicOptimizing.optimize` returns `LogicOptimizationCandidate`, retaining source
and candidate owners. Each source node has one dense-index correspondence; nil
means its canonical representative is dead. Many-to-one mappings retain all
source identities/ranges through the retained source. Result nodes use the first
canonical representative's identity and range. Public construction is internal.
Inputs and state outputs are never merged or removed. All state data/control
roots survive and are remapped without changing polarity, edge, reset priority,
initial value or state order. All port identities, directions and bit order survive.
Constant folds count nonconstant source operations reduced to constants; common
subexpressions count canonical-key reuse; removedNodes is source minus result.

## Runtime Flows
Canonicalize in validated topological order. Mark outputs, every input/state
output and state data/control as live; traverse canonical operands. Rebuild only
live nodes through BitLogicBuilder. No partial candidate escapes failure.

## State, Ownership, and Lifecycle
One noncopyable workspace owns fixed-capacity arrays and dictionary derived from
source node/port counts. No dictionary enumeration controls meaning. Scoped Span
borrows cannot escape. Scratch reservation is released on success/throw; result
storage is retained and charged. No shared mutable state or target branches.

## Failure, Concurrency, and Constraints
Every scan/edge consumes work with checkpoint. Checked arithmetic precedes
allocations; temporary maps, dictionary payload, scratch buffers and result
origin storage count toward cumulative managed storage. Dictionary/Array allocator
headers and capacity rounding are not RSS accounting, consistent with lower IR.
Invalid model, resource, cancellation and deadline remain distinct typed failures.

## Verification and Change Impact
[LogicOptimizationTests](../../../Tests/LogicOptimizationTests) compare independent exhaustive evaluation, origin mappings,
state controls and checked S4 proofs. Source-to-optimized integration composes S2
frontend/lowering. Native/WASM/Embedded probes execute the public existential.
Legacy host API, mapping and four-state optimization equivalence are not claimed.
