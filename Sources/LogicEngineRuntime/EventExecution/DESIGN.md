# EventExecution

## Purpose and Scope
Host four-state simulation. Parent: [Runtime](../DESIGN.md). No children.

## Responsibilities and Boundaries
Own schema-v4 source/verified-mapped simulation requests/results and an actor
conforming directly to LogicSimulationExecuting / Foundation.Engine. Compile and
evaluate through portable requirements; own no event or cell meaning.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Runtime](../DESIGN.md) | parent | Host ownership | Composition | No wrapper |
| [Simulation](../../LogicSimulation/DESIGN.md) | depends on | Compile/evaluate | Four-state events | Binary proof is separate |
| [VerifiedArtifacts](../VerifiedArtifacts/DESIGN.md) | depends on | Actual-cell reload | Exact mapped input | No legacy metadata |

## Architecture
```text
source -> elaboration -> RTL simulation model -> exclusive state -> ordered events
receipt -> checked actual-cell reload -> mapped simulation model -> exclusive state
  -> retained exact-input specification -> assertion matching
  -> immutable request/observations/acceptance -> evidence-bearing result
acceptance + expected current request -> exact reread + simulation replay -> checked assessment
```

## Contracts and Invariants
Exactly one source bundle or actual-cell receipt is selected. Inputs are fixed
exact bytes. An initial event at time zero records declared defaults/X/Z before
user events. Values are explicit MSB-first 0/1/x/z strings with arbitrary width;
empty/invalid strings and mismatched port widths fail. Times are nondecreasing.
Blocking/NBA, edge, reset and latch meaning belong to portable simulation. Kernel
context spans source compilation and all events. No four-state equivalence claim
is inferred from the mapped two-state proof. Every write/reread succeeds before
returning a result; observations contain canonical port IDs and scalar ordinals.

A schema-1 retained specification binds the exact source/receipt references, logical source names, source
roots/top and ordered stimuli. Assertion IDs are unique and nonempty. Each assertion
selects an observation ordinal (initial observation is zero), exact time, output
port ordinal and complete MSB-first value. X and Z are literal values, never
wildcards; uppercase spellings normalize to lowercase. Empty specifications,
malformed assertions and mismatched input/stimulus bindings throw typed errors.
Missing observations/outputs, time mismatch and differing values produce retained
explicit violations and a failed assessment. No specification produces unassessed,
never passed. Completed execution is separate from assertion acceptance.

The schema-2 acceptance artifact binds the request, observations and specification
artifacts, producer/algorithm identity, assessment and `operationalInputs`.
Request `inputs` remains the immediate selector set. The operational closure is
owned by Runtime: direct simulation inputs plus only successfully verified artifact
reads during specification intake and source/checked-synthesis replay. Mapped replay
includes its request, source/library, actual saved netlist/identities/bit design,
proof and, when actually consumed, STA result/design/SDC/PDK inputs. A source-only
simulation does not invent a PDK dependency. Output writes/rereads and reload
metadata are outside this collection. Exact references are deduplicated and sorted
bytewise by full-reference JSON encoded with sorted keys and unescaped slashes.
Result provenance inputs exactly equal this retained closure. The acceptance's
`operationalInputBindings` supplies one actually verified availability per reference
in the same order; when a reference was read through multiple availabilities, the
bytewise smallest canonical full-binding JSON selects its retained availability.
Checked reload independently reconstructs and compares both arrays. Consumers can
retain the read sources without parsing nested domain artifacts or guessing paths. No caller-declared
extra input can extend it. Schema1/algorithm1 acceptance cannot establish this
closure and is rejected; producer1.2/algorithm2 own the new representation. LogicSimulationArtifactLoading.load requires an expected
current request and caller-owned limits; it verifies exact bytes, exact request
equality, source/receipt replay and regenerated observations/assessment/operational
closure. Missing, extra, reordered or forged closure members fail even when the
acceptance bytes have been rehashed. Consumers compare the checked producer,
assessment and operational closure with returned execution provenance before using
the checked assessment. Original process-image qualification remains separate. Rehashed
forged observations or assessments cannot establish acceptance. Consumers must use
this checked load before accepting saved evidence. Neither execution nor matching
assertions establishes coverage completeness, process trust or release approval.

## State, Ownership, and Lifecycle
The actor owns immutable Sendable dependencies. Each call owns its noncopyable
model-bound state and context. Checked mapped prerequisite loading, compilation and events share the same
cumulative context, host byte budget and run deadline.

## Failure, Concurrency, and Constraints
Host byte/time and kernel budgets are explicit. Typed input/codec/kernel/persistence
failures propagate. Unknown initialization is never silently zeroed. No stream,
shared mutable simulation state or implicit random stimulus is introduced.

## Verification and Change Impact
Runtime API/CLI tests own source bit/X/Z/defaults, real-cell events, current schema
and failures. SimulationAcceptanceTests own exact specification binding, literal
X/Z and width matching, explicit violations, stale/rehashed artifact refusal,
checked replay and real CLI nonzero failure. Portable simulation tests own
scheduler and cell semantics. This host-only change preserves portable state,
isolation and all Native/WASM/Embedded simulation contracts.
