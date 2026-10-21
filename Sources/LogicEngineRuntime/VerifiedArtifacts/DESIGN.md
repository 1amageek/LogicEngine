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

## Controlled Reload

This additive host profile closes caller accounting in `load`. Receipt/request
schemas, exact source/library rebuild, canonical graph/netlist comparison,
independent RUP recheck and required exact-input STA remain the original pipeline.
The legacy load API is unchanged. Controlled codecs and strict Timing replay
are integrated on the package's locked public dependency graph.

### Current facts and minimal seams

| Current path | Controlled seam | Owner |
|---|---|---|
| `load` constructs a private context/control | Existing caller context plus its actual installed accounting adapter; no reset | LogicKernelCore and this component |
| IO caps declared bytes then uses bare store read | Opt-in controlled read, bounded chunks, integrity, explicit close | [ArtifactStorage](../../LogicEngineCore/ArtifactStorage/DESIGN.md) |
| Receipt/request/RUP JSON allocates DTOs before table admission | Schema-derived admission and checked validation loops | This component |
| Graph decode and equality encodes allocate records without host admission | Controlled codecs returning value plus retained anchor | LogicDesignSerialization |
| Source/Liberty copies precede reservation; parser usage transfers afterward | Preadmit copies; forward actual source work/storage synchronously | Runtime composition and original TimingCore parser |
| Saved STA decoding and replay use ordinary resources | Timing-owned controlled codec and strict prepare/replay | TimingEngine |
| Context has run-local reservation tokens; returned IR has no external lease | Separate temporary scope and transferred retained anchor | LogicKernelCore and this component |

`LogicRUPCertificateCodec` stays in this component of `LogicEngineRuntime`. There
is no `LogicEngineSerialization` target, and no LogicProof reverse dependency is
introduced into LogicDesignSerialization.

### Proposed public operation

```swift
public protocol LogicSynthesisArtifactControlledLoading: Sendable {
    func load(
        _ receipt: LogicArtifactBinding,
        limits: LogicRuntimeLimits,
        context: inout LogicKernelContext,
        resources: LogicReloadResources
    ) async throws -> (value: LogicVerifiedSynthesis, retention: LogicReloadRetention)
}
```

`LogicReloadResources` is the actual caller-installed accounting adapter, not an
engine, generic allocator or independent budget. Its injected untyped host control
checks per-call cancellation B/deadline and admits actual resource charges. The
context retains its original control A. Runtime must check that the adapter is
EXACTLY the one installed in the supplied context. Use `context.requireAccounting(expected: resources)`, whose lower contract
compares the actual accounting objects by identity. Equality of counters is not
evidence of this join.
The public adapter initializer is `LogicReloadResources(control:)`. Its
`LogicReloadResourceControlling` requirements are untyped `check`,
`observeBitWidth`, `charge(LogicResource, amount:)`, atomic `reserveStorage`,
`chargeArtifact(ArtifactSourceWork)` and `retainArtifact(ArtifactSourceExtent)`.
One original caller policy backs these callbacks; this adapter adds no counters
or independent ceilings. It implements the portable `LogicKernelAccounting`
and CF `ArtifactSourceControl` requirements;
its synchronized first external cause survives a portable
`LogicKernelError.externalAccountingFailure` sentinel and remains inspectable as the primary cause
at the host boundary. An anchored lower failure remains the whole secondary
value; inspecting its cause never transfers or releases its private lease. After an external failure this invocation adapter remains
failed; it cannot be rearmed or silently reused for success. The original caller
policy may back a fresh invocation. Arbitrary errors do not enter the Equatable
kernel enum.

The native actor implements this protocol directly. No default controlled method
calls legacy `load`, bare store `read`, or ordinary STA. Unsupported store/codec/
strict-transform capability is a typed failure, not a reduced proof profile.

### Runtime flow and admission

```text
original context + actual accounting adapter + per-call B
 -> controlled receipt/request read, schema admission, decode and validation
 -> exact source/Liberty rebuild and controlled graph/netlist/source comparison
 -> original CNF/miter and independently checked controlled RUP import
 -> required controlled saved-STA decode and strict exact-input STA replay
 -> final A/B checks -> original checked value + immutable retained anchor
```

The additive controlled profile accepts UTF-8 JSON with unique object keys.
Canonical producer receipts, requests and RUP already use this representation.
Other encodings and duplicate keys fail explicitly with the decoder cause and
position; the legacy Foundation profile remains unchanged. Unknown fields retain
the existing ignored-field behavior (`rejectUnknownFields: false`). No bytes are
rewritten and no failed input falls back to Foundation. The existing bounded
intake admits its lexical arena, typed containers, strings and nested elements
before growth. Schema, number and enum meaning remain owned by the original DTOs. Use the existing PDKDiscovery audited bounded-document decoder with its additive
raw-span input. It supplies iterative lexical and typed-container admission;
Runtime owns receipt/request/RUP schema and semantic audits. This introduces no
JSON lexer or alternate canonical decoding framework. RUP clause/literal tables and conversion scratches have their own
source-derived counts. Raw data, decoded DTOs, conversions and old/new payloads
that coexist are admitted simultaneously. Guessed byte multipliers and admission
after construction are insufficient. Foundation-private parser workspace and
allocator buckets are opaque exclusions; this code's Data, String, arrays,
dictionaries and decoded DTO payloads are included. This is managed-payload
accounting, not a hard RSS or synchronous Foundation interrupt-latency guarantee.

Every owned validation, hash/copy, comparison and construction loop charges
scheduled work and checks cancellation at bounded intervals. In particular,
request policy uniqueness cannot run the existing quadratic comparison sequence
without work admission. Byte/count/stride arithmetic is checked before allocation.
Checks occur after external charge/reservation callbacks, before another reserve
or allocation. Opaque Foundation operations have pre/post checks.

### State, ownership, and failure

The lower controlled retention scope supplies begin/finish/discard. Temporary
kernel/codec workspace is released by its actual lifetime; work, allocation and
reservation counters remain cumulative. A context's destruction is not a refund
or a returned backing owner. Success transfers retained backing leases into the
Runtime anchor; failure discards only releasable storage. The Runtime anchor
retains all exact lower codec/source/Timing anchors required by the returned
request, graphs, proof and compiled source facts, and no needless decoder/raw
snapshot scratch. No checked proof or IR authority is synthesized by an anchor.

Every value copy and every extracted/shared request, graph, library or proof must
keep the accompanying retention anchor alive. Bare extraction does not gain an
implicit lease. Runtime/CLI owning holders keep both until last use; last anchor
release refunds exactly once, independently of cancellation. Kernel conservative
invocation usage and the outer accountant's live bytes are distinct measurements.

Host failures retain their phase, original primary cause, optional close/cleanup
cause and required error-payload anchor outside `LogicKernelError`. Do not replace
an accountant cause with a formatted description. The existing CF controlled source owner closes on every exit, including
cancellation, before returning a successful read. Its typed composite read/close
causes remain inspectable; Runtime does not fabricate a replacement cleanup owner. Publication
requires successful integrity/close, all original proof/STA checks and final A/B
checks. No failed or cancelled attempt publishes a checked value.

### Focused verification and change impact

| Evidence | Required discriminator |
|---|---|
| Real legacy and controlled receipt replay | Identical canonical graphs, source/library/operating premises and required STA |
| Byte-admitted large policies and nested DTOs with tiny storage/work | Refusal before owned growth or uncharged comparisons; exact originating cause |
| Pre-spent context, Liberty and STA work/storage | Same ledger, no reset, simultaneous live payload admission |
| Distinct B cancelled in read/reserve/validation/STA await | No publication or post-cancel owned work; A live, cleanup awaited, owner reusable |
| Corrupt/short/growing file and read plus close failure | Original integrity/close causes; cleanup completed or explicitly failed; no partial success |
| Copied result/error and extracted shared graph | Temporary release at phase end and retained last-copy refund |
| Rebound source/graph/RUP/STA and old schema | Existing strict recheck failures preserved |

The final Native host focused run passed 19 declarations / 31 expanded cases
in six suites with zero skips. It includes all controlled reload, artifact-read,
Timing-digest and producer-audit cases, mandatory full typed STA replay, original
RUP binding, and the current legacy CLI save/reload and rehashed-metric refusal.
The unchanged 32 declarations / 32 cases from the preceding qualified run compose
to 51 distinct declarations / 63 cases; they were not all rerun. The sole
comprehensive-review finding, missing producer-token custom-decode work, has a
genuine four-case RED and a finding-limited GREEN recheck with no remaining
findings. Earlier operational and behavioral failures remain recorded. CLI
adoption of the controlled API, portable execution, whole-phase/history and
physical or process qualification are outside this finite host gate.

### Controlled source-phase composition

Each exclusive source/decoder phase captures the caller context's remaining
storage, allocation, reservation and work ceilings. Before every action it
forwards actual admission to the exact installed adapter; local phase counters
commit after that callback and before post-callback cancellation. On success AND
failure, import the spent counters exactly once using
`context.importAccountedPhase(..., expectedAccounting: resources)`. This import
is local-only and noncancellable: it does not call the outer accountant again or
create a lease. Context managed storage is a conservative phase-peak carry, while
outer leases follow the actual lower owner lifetime. Work and cumulative
allocation/reservation charges never reset or refund.

The same original A control is copied from `context.checkpointControl` into
async/source adapters. Their checks include A, per-call B and Task cancellation.
The invocation-private checked snapshot holds only exact already-verified binding
bytes with anchors, for synchronous reuse by the original reload helpers. Every
lookup retains aggregate logical-read ceilings without claiming another physical
hash/read/copy. Missing transitive inputs fail; they never fall back to the legacy
store. Snapshot payload/metadata are temporary and must not survive in the final
anchor unless an actual returned lower owner retains that exact payload.

The original Liberty normal-power validator calls its synchronous `admit` hook
before every source work/reservation action. After initial parse import, its
retained source accountant explicitly enters context-mediated mode: that existing
hook owns actual work/storage admission in the supplied context, while source
resource methods retain A/B checking and avoid a second outer charge. This mode
is confined to those actual original validator calls, not a generic accounting
disable switch.

### Controlled decode failure transfer

The raw-span PDK decoder and controlled manifest decoder return their private
retention on both success and failure. Runtime preserves the entire
`PDKControlledDecodeFailure` and `LogicGraphCodecSourceFailure`, including when
an original caller error must be promoted to the primary cause. No catch unwraps
a naked lower cause. A failed phase imports already-spent counters exactly once
and then propagates the anchored failure; any distinct import/cleanup failure is
added as a secondary cause without replacing that owner.

Receipt/request audits preadmit CF canonical SHA-256 ID constructor buffers from
the exact fixed wire domain/version/algorithm/digest lengths before the original
initializer executes. The controlled profile admits those SHA-256 IDs because
the original Runtime integrity path requires SHA-256. UInt8-key kernel limits
use their actual alternating-array Dictionary wire representation and a
source-derived encoded pair count (including duplicate keys); generic object-container admission
alone does not cover that backing. Unknown object fields remain ignored.

### Producer custom-decode work admission

The receipt audit also owns additional CF `ProducerIdentity` token-validation work for `identifier`, `version`, and a present non-null `build`. It invokes the existing checked three-times-UTF8 token admission before CF custom decoding: first-character, last-character and Unicode-scalar scans remain the original CF implementation. Generic JSON parsing is separately charged. No CF token validation, Unicode conversion, length restriction, schema interpretation, or original error mapping is duplicated or changed.

`ControlledProducerAuditTests` uses actual synthesized receipt bytes and a digest-rebound legal producer token. Work sampled only around the production receipt audit excludes generic parser work. Long-token and original-token differences detect an omitted custom scan; one-below observed custom-audit work, original A/per-call B cancellation, actual CF failure, and last-copy document/failure refunds exercise the same accountant and lower owner. The original implementation failed all four long-token work-delta cases; the
existing token-admission hook then passed these cases without changing CF
construction, validation or error semantics.

### Controlled phase and snapshot composition

The controlled load requirement and implementation are `nonisolated(nonsending)` async. They remain on the caller isolation while exclusively borrowing its `inout LogicKernelContext`; the noncopyable context is neither copied nor made Sendable. The implementation reads only the actor's immutable Sendable artifact store and uses the existing isolation-inheriting static replay helpers, without accessing mutable actor state.

The caller keeps exclusive `inout LogicKernelContext` access while an asynchronous
source phase runs. `LogicReloadPhase` captures the remaining storage, allocation,
reservation and work ceilings plus original control A. Every actual source
admission synchronously forwards to the same external adapter before action,
checks A/B after callbacks, and commits actual spent counters. Success and failure
import those four counters exactly once through `importAccountedPhase`; import
has no external charge/refund and does not observe cancellation. The outer lease
controls live bytes, while the parent context conservatively carries phase peak
storage. These are intentionally different quantities.

Controlled STA replay keeps the canonical ordinary `STAExecutionLimits()` path-state and path-work values because they are part of the immutable effective configuration and its digest. The Logic table capacity still bounds parser/host tables and the existing scenario/design/path staging; it does not redefine those STA semantic fields. The same original phase accountant independently enforces the remaining caller work, storage and cancellation bounds before actual transforms. Saved payload fields never supply execution-limit authority, and full typed payload equality remains mandatory.

CF work details retain actual read/hash/page counts. Their `workUnits` forward
once through the Kernel work hook; the artifact-detail callback receives zero
workUnits to avoid charging the same work a second time. PDK parser events map
to scheduled Kernel work; owned/temporary byte reservations use that phase's
actual outer storage leases. Nesting remains a separately bounded live count.

`LogicReloadCapture` reads the exact receipt/request and their explicit artifact
closure once under the controlled store capability. The immutable snapshot
holds exact bindings, already verified Data and read anchors. Header capacity is
derived from actual input/reference counts before array creation. Synchronous
original reload helpers obtain bytes only by context-bound snapshot lookup.
Uncaptured transitive reads refuse; a snapshot cannot grant authority by shape.
Legacy cumulative logical-read byte admission still runs on every original read;
physical read/hash/copy charges occur only when actually performed. Snapshot Data
and entry-table offers end with replay, not with the returned verified result.

Controlled Liberty parsing admits the Data-to-Array boundary before conversion,
forwards parse admissions to a source phase, and imports it on success/failure.
After import, the retained source's normal-power validator uses the original
inout-context admission hook before its resource callback. That retained source
checks A/B but does not charge the same hook again. `sourceStorageCredit` is zero
for this path; the legacy parse-usage postcharge sequence remains unchanged.
Controlled manifest decode/validation uses the PDK owner's paired result and
never repeats the unmetered legacy validator.

RUP controlled encoding owns the fixed schema-v1 wire serializer. Exact integer
decimal widths and actual clause/literal counts size final Data before growth;
its field order matches legacy `JSONEncoder.sortedKeys`. A separate 20-byte
scratch offer covers a signed 64-bit decimal conversion and ends before the
retained output anchor is published. Controlled decoding reuses the original
CNF/RUP builders with preadmitted literal conversion scratches.

A failed source Kernel phase uses `retainFailureScope` without cancellation or new
admission, because an existing builder diagnostic may share generated symbol or
table backing. The inspectable Runtime failure keeps that conservative admitted
scope and whole lower errors. Successful phase scratch is not transferred by this
failure-only rule. A load failure also keeps the already-decoded receipt/request
and completed phase anchors when a saved field contributes a diagnostic value.

Strict transform accounting and strict source evidence are separate contracts.
Replay preserves the original STARequest's `requireStrictSourceEvidence` value.
Ordinary saved results still require the original `validateTiming` predicates and
exact payload replay; they do not gain source qualification. Only an original
strict-source request requires the separate source-evidence validation against
its freshly prepared owner. No ordinary saved result is silently upgraded.

The mapped-to-TimingDesign projection has one shared implementation. Controlled
calls preadmit its exact count-derived arrays, generated decimal names and
connection/set bucket offers, and keep that temporary owner through controlled
JSON publication. Standard calls use the same connectivity/name rules without
changing the old JSON formatting. These are Runtime-owned interchange transforms,
not a second STA parser or saved-result validator.

Operation-local phase and bridge metadata is admitted before their heap owners
are constructed. Factories offer the logical stored fields plus the Swift host
object header; allocator bucket/RSS slack is excluded. Each phase lease combines
its requested payload and its own fixed stored-field/header offer in one atomic
outer reservation. A source phase's constructor offer is part of the same four
counters and is imported even if a post-reservation A/B check fails before the
phase object is created. Caller-created immutable policy/grant configuration is
not recharged as operation payload. No callbacks occur while metadata state is
locked, and no constructor adds a new budget or policy.

The focused controlled-reload tests reuse the existing actual synthesis and
mandatory Timing fixtures. They verify independent checked proof binding,
pre-spent context carry, exact installed-accountant identity, first/mid-operation
B cancellation, original caller causes, explicit read grants, source byte/hash
work, canonical RUP parity, ignored unknown fields, duplicate/non-UTF8 rejection
and copied-anchor final refund. Timing still executes rather than consuming
saved metrics. The fixed Swift 6.4.0 Native host run and actual regular CLI
build execute these predicates; source/object/binary closures bind each product
to the tested snapshot. Runtime and lower preparation each use the original
shared caller policy; test fixtures do not create a second production reload budget.

### Controlled Timing-design digest admission

The exact call in `controlledTimingReload` remains the public Foundation
`SHA256ContentDigester.digest(data:using:)` path. In the fixed CF `26.1021.1`
source (`7b5ab9cf`), that adapter materializes `[UInt8](data)` before the original
SHA-256 session. It does not borrow the Data storage. Its instance
`foundationDataCopyCost(byteCount:)` therefore applies in addition to the static
`SHA256ContentDigester.managedCost(byteCount:)`. The owning public costs include
the actual copy, SHA/session/finalization scratch, normalized digest backing and
scheduled visits; backend-private allocator workspace remains excluded. Runtime
must not duplicate those lower-private layouts or substitute an estimated factor.

```text
existing encoded TimingDesign + original source phase
 -> public copy/hash scalar costs + checked sums
 -> same accountant work admission and A/B check
 -> temporary copy/hash reservation and A/B check
 -> retained digest reservation and A/B check
 -> unchanged digest(data:) and A/B check
 -> release temporary scratch
 -> original design digest/byte-count comparison with digest anchor alive
 -> release digest anchor before STA request preparation
```

The internal helper returns `(value: ContentDigest, retention:
LibertySourceStorageReservation)`, using the existing reservation contract. It
introduces no public factory, protocol, codec or hash implementation. The cost
planner is scalar-only, overflow-checks temporary and work sums, propagates the
public `ContentDigestError` unchanged, and reports aggregate overflow as
`LibertySourceError.arithmeticOverflow` before any reservation. Both temporary
costs coexist during hashing; only the public retained digest cost survives the
helper return. Every extracted/copied digest keeps its paired reservation through
last use. Failure drops the admitted reservations without accounting or checking
cancellation during release. The existing outer phase imports actual spent
counters exactly once and preserves original caller/lower causes. SHA bytes,
algorithm, saved-design predicates and subsequent STA replay remain unchanged.
Legacy bare hashes are outside this controlled helper and remain unchanged.

`ControlledTimingDigestCostTests` owns exact original-digest parity, distinct
temporary/retained lifetimes, public-cost work admission, tiny temporary/combined
storage refusal, callback-triggered cancellation before any later reservation,
scalar overflow refusal and the actual pre-spent Kernel/source-phase bridge with
copied-anchor final refund. All six declarations / eleven expanded cases pass
in the final locked public graph. They supplement rather than replace the
actual mandatory STA controlled-reload test and its exact typed-payload replay.
