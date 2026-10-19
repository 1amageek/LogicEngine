# CircuitEquivalence

## Purpose and Scope
Checked combinational and state-preserving inductive equivalence between bit
graphs and actual mapped graphs. Parent: [LogicProof](../DESIGN.md). No children.

## Responsibilities and Boundaries
Own total input/output/state correspondence, actual-function Tseitin miter,
proof binding and independently replay-confirmed counterexamples. No mapping,
retiming, state recoding, filesystem digest, STA or release approval.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicProof](../DESIGN.md) | parent | Proof composition | Equivalence authority | Status is insufficient |
| [CDCLSearch](../CDCLSearch/DESIGN.md) | depends on | SAT assignment/certificate | Injected search | Validate assignment binding |
| [RUPChecking](../RUPChecking/DESIGN.md) | depends on | Checked proof | Independent proof acceptance | Verify formula owner binding |
| [BinaryRelations](../../LogicSimulation/BinaryRelations/DESIGN.md) | depends on | Direct Boolean replay | Independent concrete evaluation | No Tseitin helper reuse |

## Architecture
```text
two exact designs + total bit correspondence + identical initial ranges
    -> shared input/current-state variables -> actual-function Tseitin miter
    -> SAT -> validate CNF assignment -> independent replay -> confirmed difference
    -> UNSAT certificate -> independent RUP check -> bound inductive proof
```

## Contracts and Invariants
Correspondence is a bijection covering every flattened input/output/state bit.
Mapped designs retain their exact library. Actual-cell proof admission applies
MappedGraph standard-netlist realization: specified startup metadata is not a
physical initial-set premise and is refused for current cells. Bit-to-bit abstract
initial-state proofs remain supported. Initial-state ranges must match per
state pair; mismatch is an inadmissible problem, never equivalent. State kind and
FF effective root edge must match the admitted state-preserving profile. No environment
constraints are assumed: all binary inputs and all current states are quantified,
which is stronger than restricting reachable states. Control history, sampled
event updates and asynchronous updates are compared in addition to outputs.
FF sampled updates are guarded by the active clock level; checking both possible
previous clock levels reduces to this update plus asynchronous/hold behavior.
The binary relation contract owns primitive update meaning. This establishes a
state-preserving induction, not bounded trace or structural evidence.
Equivalent construction is private and requires a checked proof of this miter;
different construction requires replay of both original models and an actual
output/event-update difference from an allowed initial state. An arbitrary-state
witness with unestablished reachability, or a control-only mismatch without a
concrete stabilized event difference, is inconclusive with the replayed witness.
Replay executes both logical-root previous-control values for FFs, simultaneous updates,
asynchronous reset and transparent stabilization before comparing final outputs
and corresponding state. Initial control history is unconstrained binary and
corresponding; the proved control invariant preserves that correspondence.
Resource/control
failure yields inconclusive. Invalid models or forged evidence throw typed errors.

## State, Ownership, and Lifecycle
Problem and checked result retain immutable design/correspondence owners. Builder
and symbolic tables are exclusively owned noncopyable workspaces. Shared inputs
and current states are allocated once per correspondence pair. Scoped spans only.

## Failure, Concurrency, and Constraints
All expansion/count arithmetic and buffer growth are bounded before allocation.
Kernel context remains cumulative through encoding, solving, checking and replay.
Invalid/missing/wrong-binding evidence cannot become equivalent. All targets use
the same ownership/conformance and synchronous implementation.

## Verification and Change Impact
LogicProofTests covers all Boolean operations, port permutations, signed-width
lowering fixtures, wrong NAND/pin/control/reset, FF/latch induction, forged evidence,
limits/control and three-target runtime. S5 depends only on this checked contract.

## Persisted certificate rechecking
`LogicEquivalenceProofRechecking.recheck` rebuilds the miter for the supplied exact
problem and uses only the independent proof checker on a raw RUP certificate.
NativeLogicEquivalenceChecker implements this boundary without invoking SAT search.
CNF content equality is checked before any CheckedLogicEquivalence is constructed.
A decoded certificate is untrusted until this succeeds; owner identity binding of
the returned checked value remains unchanged.

## Actual Clock-Lineage Normalization

MappedGraph's immutable `withStateClocks` is the sole mapped clock-lineage authority.
A primary lineage supplies physical carrier = root XOR parity and effective root
edge = local cell edge XOR parity. Opaque carriers retain raw control/local edge
with parity false. BitGraph proof admission traces only actual buffer/invert opcodes
to a primary input; all other carriers retain the existing opaque profile. Traces
are bounded and charged. No cell name, origin or serialized clock metadata is used.

```text
actual graph -> immutable shape (effective kind, carrier parity)
actual function CNF -> raw control XOR parity -> root control/effective-edge relation
SAT witness -> logical previous root XOR each state parity
            -> separate physical history vectors -> original-model event replay
```

The miter retains every actual-cell function and connection. Input correspondence
and the resulting CNF compare roots across designs; equal numeric net indices or
names cannot establish root identity. Latches, resets, enable and initial-state
ranges retain their existing contracts. No new gated/generated clock relaxation
is added. Independent RUP construction/checking remains unchanged.

Counterexample replay normalizes relation comparisons only inside LogicProof.
BinaryRelations continues to expose actual physical pin controls and local edges.
`withEventControls` borrows the two exact per-state physical history vectors only
for a confirmed FF event; otherwise it returns nil without invoking its closure.
`previousControl` remains the common raw physical value only when both complete
history vectors contain one identical value; mixed parity yields nil. No FF history
is invented for latch/combinational observations or an unconfirmed event. Storage,
history buffers, trace work and independent replay use the cumulative kernel budget.

Clock-lineage shared probes require actual BUF branches, multilevel/even inversion,
odd inversion with falling-edge compensation, mixed physical histories, bit-graph
inversion, independent certificate recheck, and direct physical event oracles. Wrong
edge, connection, root and inadmissible clock derivation cannot become equivalent.
Native, ordinary WASM and Embedded use the same immutable owners and synchronous
protocol requirements. Sequential WASI execution is not parallel safety evidence.
