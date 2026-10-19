# VerifiedArtifacts

## Purpose and Scope
Exact synthesis artifacts and independent reload. Parent: [Runtime](../DESIGN.md).
No children.

## Responsibilities and Boundaries
Own schema-v4 receipt, schema-v1 raw CNF/RUP codec, exact digest bindings and
verified reload. Graph codecs belong to LogicDesignSerialization. Checked proof
construction belongs exclusively to LogicProof; JSON records never deserialize it.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Runtime](../DESIGN.md) | parent | Host artifact boundary | Composition | No release decisions |
| [Codec](../../../../LogicDesign/Sources/LogicDesignSerialization/Codec/DESIGN.md) | depends on | Bit/mapped/Verilog codecs | Rebuild validated owners | Library verified separately |
| [Equivalence](../../LogicProof/CircuitEquivalence/DESIGN.md) | depends on | Proof recheck | Rebuild miter and check RUP | No SAT search on reload |

## Architecture
```text
receipt -> digest-checked source/config/library/bit/Verilog/sidecar/certificate
  -> library rebuild -> validated graph decode -> structural import
  -> exact correspondence -> rebuilt miter -> independent RUP check -> checked owner
```

## Contracts and Invariants
The receipt binds source order/names, request configuration, algorithm identity,
exact library bytes, original bit graph, actual netlist and identities, proof and
metrics. Presence/digests alone never establish equivalence. Reload checks that
imported physical connectivity matches the identity sidecar and rebuilds the same
miter before certificate checking. Returned checked owners cannot be constructed
by consumers. Old schemas and metadata evidence are rejected. Standard Verilog is
the physical interchange; its identity sidecar retains grouping, state IDs and
origins. Abstract initial demands in JSON never create physical startup.

## Failure, Concurrency, and Constraints
Every read verifies size and SHA-256 within explicit byte limits. Reload uses the
minimum of saved and caller parse caps without changing canonical ID allocation.
Generated artifact reread bytes are admitted before publication, including the
completion receipt; failed budget admission cannot create a completion receipt. Missing/partial,
wrong-library, wrong-CNF, tampered certificates and mismatched configuration fail.
No cache/resume accepts merely matching run IDs; no search-state checkpoint exists.

## Verification and Change Impact
Runtime tests own positive reload, corruption and partial publication. Downstream
consumers must consume the checked reload contract before functional acceptance.
Raw receipt/metric DTOs alone grant neither functional proof nor release authority.

Reload also repeats source elaboration/bit lowering and exact-input Native STA when
requested. Saved bit graph and STA payload must match these regenerated values;
rewriting digests around a forged graph or metric does not establish admission.
The final public receipt binds the measured executable producer build and fixed
deterministic seed zero. Replay observation is distinct from private checked proof
authority and never constitutes tool qualification.

Checked reload regenerates TimingDesign v2 alias/constant connectivity and repeats
Native STA including static and unconstrained endpoint coverage. Rebinding digests
around altered static facts, missing aliases or invented coverage cannot pass.
Earlier synthesis algorithms are refused; inputs can be resynthesized under the
current conditional-model contract below.
Required slack admission rejects unconstrained coverage even when another endpoint
has a numeric slack. Native exact-route exception analysis is repeated on reload; altered excludedChecks
with rebound digests cannot become checked coverage.

Historical receipt schema2 / algorithm5 / producer1.3 bound the exact request realization
policy. Reload verifies receipt/request agreement, independently validates the
imported graph policy and rejects startup metadata or logical constants that
cannot satisfy it. Rehashing the request/receipt around a changed policy cannot
upgrade logical constant drivers to physical tie cells. Source/graph/proof/STA
regeneration remains required; successful replay is not release authorization.

## Conditional functional-model receipt

Receipt schema4/algorithm7/producer1.5 bind schema-7 requests, original policies,
validated-unused outcomes and every expanded instance condition. Older receipts
require resynthesis. Reload reopens exact source/library, revalidates lower outcomes,
recompiles, reexpands over the imported graph and compares every saved record before
rechecking the original all-input/current-state proof. STA receives/replays the same
resolved assumptions and exact library/corners. Rehashed policies/PG values/roles,
missing instances and decoded outcomes grant no authority. Mapped simulation
inherits the checked receipt's fixed premises; no independent supply override exists.
Source-only RTL simulation makes no actual-cell supply claim.

The request also binds its independent functional operating process scope. Fresh
reload repeats the exact manifest/Liberty fact join before accepting the expanded
conditions. Nil scope remains source-only and unjoinable; a nonnil declared scope
does not imply that baseline STA ran. When timing is requested its execution and
replay remain mandatory. Earlier receipt/request algorithms require resynthesis.

The invocation-local IO value supports opt-in successful-read reference collection
for [EventExecution](../EventExecution/DESIGN.md)'s operational input closure.
Collection records a reference only after exact read verification succeeds. It
does not record publication/reread writes; existing non-collecting callers retain
their input and budget semantics. Collection never resets cumulative byte/time
or kernel accounting.
