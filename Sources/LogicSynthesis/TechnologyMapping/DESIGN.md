# TechnologyMapping

## Purpose and Scope
Parent: [LogicSynthesis](../DESIGN.md). Portable bounded functional technology mapping. No children.

## Responsibilities and Boundaries
Own cut enumeration, exact Boolean pin matching, synchronous control expansion,
actual instance construction and actual area/depth metrics. Return an unverified
candidate; the caller owns independent proof. No Liberty parsing, STA, storage,
artifact schema migration or release approval.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicSynthesis](../DESIGN.md) | parent | Processing composition | Portable mapper | Candidate is unverified |
| [TechnologyLibrary](../../../../LogicDesign/Sources/LogicIR/TechnologyLibrary/DESIGN.md) | depends on | Validated actual functions | Exact cell/pin/state semantics | Host compiler excludes dont_use and invalid views |
| [MappedGraph](../../../../LogicDesign/Sources/LogicIR/MappedGraph/DESIGN.md) | depends on | Consuming builder | Physical pin/net validation | No legacy mapped metadata |
| [CircuitEquivalence](../../LogicProof/CircuitEquivalence/DESIGN.md) | coordinates with | Checked equivalence | Original bit versus actual netlist | No mapper fact is a proof premise |

## Architecture
```text
bit graph -> explicit synchronous data muxes -> bounded cuts -> exact pin truth tables
library ----------------------------------------------------^        |
actual pins/state/ports <---------------------------------------------+
     -> validated mapped graph -> actual metrics -> unverified candidate
caller: original bit + actual graph -> independent checked equivalence
```

## Contracts and Invariants
LogicTechnologyMapping.map is a synchronous typed-throws protocol requirement.
Policy owns cut-input, cell search-input and per-node nontrivial cut bounds (plus one terminal cut), and generated identity start; callers
choose operational values. Packed UInt64 truth tables support at most six cut
inputs. Cell search has its independent one-to-six input bound; it counts functional combinational support or unbound sequential pins, excluding fixed clock/reset pins. Repeated physical pins must not be rejected by a smaller cut bound. Enumeration and truncation are deterministic, not a global optimality claim.
Selection compares estimated cover area, depth, stable cell ID and pin binding.
Input inversions and output inversions require actual matched inverter cells;
constants remain logical drivers under `standardNetlist`; `physicalCells` requires
actual tie outputs before publication. The caller explicitly selects the policy.
Tie bootstrap uses exact combinational cells with no input pins and constant output
functions; every physical output receives its own net. Existing opposite-value
outputs are reused. Missing bootstrap cells are unsupported, never supply aliases
or mutually dependent logical ties. Repeated inputs and tied pins are
function-checked. All physical outputs of multi-output cells get distinct nets.
State bits, IDs, order and port identities/order survive. Specified initial
ranges are preserved as source demands and refused when current cells cannot
realize them; they are never changed to unspecified. Unspecified FF/latch startup
remains admitted. Lower realization validation runs before metrics/candidate
publication. Enable
and synchronous reset become data logic with reset priority preserved. FF edge,
latch polarity and asynchronous reset polarity/value require exact cell controls;
an asynchronous reset never becomes a data mux. Sequential next-state and state
output functions are checked for all binary data/current-state/control assignments.
No match is unsupported, never an approximate cell or proof success.

## Runtime Flows
Expand OR/XOR/select to an acyclic AND/invert basis while retaining original dense-node correspondence; normalize controls, enumerate cuts in connection topology, match actual functions,
select covers, materialize live roots and state/control connections, publish through
MappedGateBuilder, and measure actual instances/topology. Proof remains caller-owned.

## State, Ownership, and Lifecycle
Immutable Sendable source/library/candidate owners. Noncopyable run-local workspaces
own bounded tables; scoped Span borrows do not escape. One cumulative context crosses
all stages. The normalized graph is immutable run-local data, never an independently charged public artifact. Scratch reservations are released on success/failure; output owners
and origin correspondence remain charged. No shared mutable state or target branch.

## Failure, Concurrency, and Constraints
Checked capacity arithmetic precedes storage allocation; cut tables, pin search,
function evaluation, cover construction and temporary/result buffers are admitted.
Every potentially large loop charges work/checkpoints. Managed storage models admitted payload capacities, including simultaneous buffers; allocator headers/rounding and RSS are not claimed. Repeated cut-attempt buffers and retained pin-pattern copies also charge cumulative allocation bytes before allocation; final netlist/origin payload charges outputBytes. Invalid model, unsupported,
resource limit, cancellation and deadline remain distinct. No partial candidate escapes.

## Verification and Change Impact
LogicOptimizationTests mapping fixtures and shared three-target probes own exact
function/permutation/inversion/multi-output/constant/state/initial/origin behavior,
wrong-cell/pin/control counterexamples, bounded refusal and original-to-mapped proofs.
Host Liberty compilation integration verifies eligibility and exact functions.
Runtime owns host API/CLI/artifact admission and checked replay; downstream
consumers independently admit its exact receipt contract.

## Recomputed artifact metrics
`LogicMappedDesignMeasuring.measure` exposes the same actual-library area and
function-support/topology depth calculation used at candidate emission. It owns
no mapping search and accepts only a validated mapped owner. Runtime reload uses
this contract to reject persisted metric drift instead of duplicating the algorithm.

Both tie-match optional slots and retained pin patterns are admitted in the owning
workspace reservation before allocation. Exact constant-only normalized functions
are evaluated with zero independent inputs; cell names never imply tie semantics.
The state/ownership matrix remains the same on Native/WASM/Embedded: immutable
Sendable source/library/policy/candidate, exclusive noncopyable mapping/matcher
workspaces and cumulative context, existing Mutex-backed cancellation. No borrow,
callback or mutable workspace crosses suspension or escapes its scope.
