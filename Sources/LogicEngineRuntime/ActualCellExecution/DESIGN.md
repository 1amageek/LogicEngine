# ActualCellExecution

## Purpose and Scope
Host source-to-real-cell synthesis. Parent: [Runtime](../DESIGN.md). No children.

## Responsibilities and Boundaries
Own schema-v7 synthesis requests/results and the concrete actor conforming directly
to CircuiteFoundation.Engine through LogicSynthesisExecuting. Inject artifact,
frontend, lowering, optimizer, mapper and proof contracts. No circuit meaning,
SAT exploration, timing algorithm, workspace policy or release approval is owned here.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Runtime](../DESIGN.md) | parent | Host composition | Ordered lifecycle | No wrapper |
| [VerifiedArtifacts](../VerifiedArtifacts/DESIGN.md) | depends on | Checked reload | Evidence binding | Decode grants no authority |
| [Library compilation](../TechnologyLibraryCompilation/DESIGN.md) | depends on | Owned Liberty compiler | Exact physical functions | No inferred gates |
| [Proof](../../LogicProof/CircuitEquivalence/DESIGN.md) | depends on | Checked equivalence | Original bit to imported cells | Two-state only |
| [STA](../../../../TimingEngine/Sources/STAEngine/DESIGN.md) | depends on | Existing STAExecuting | Corner/condition analysis | No substitute delay estimates |
| [PDKCore](../../../../PDKKit/Sources/PDKCore/DESIGN.md) | depends on | Public manifest codec/validator and declared process/corner/asset facts | Functional premise join | Source declarations are not electrical qualification |

## Architecture
```text
exact source + Liberty -> elaborate -> word -> bit -> optimize -> actual mapper
  -> structural export/import -> independent original-to-imported proof
  -> requested STA / area checks -> immutable files -> final receipt
```

## Contracts and Invariants
One cumulative kernel context spans every synchronous stage and final proof.
Every source materialization is byte-count/digest checked, even with an injected
store. Explicit host byte, parse and elapsed budgets precede decoding. Requests
select every resource/capacity; no hidden production limit is inferred. Generated
IDs and deterministic search bounds are configuration inputs, with a fixed
algorithm identity. Input references are unique in first-use order; semantic
source and corner roles remain in their request fields. A functional proof is required before candidate publication.
Required area/STA/power checks are independent: unknown power cannot satisfy a
power limit. Missing STA, unmeasured required slacks, or unmatched corner/library
binding cannot pass. STA receives a TimingDesign projected from actual physical
pins, explicit port/net aliases and binary constant drivers. TimingEngine owns analysis. Constraint failure describes
this candidate only. Old metadata request schemas are refused by this engine.

## Runtime Flows
The actor owns ordered intake/compute/STA/persist. Kernel work is synchronous;
Task cancellation and a monotonic deadline are checked through LogicRunControlling.
No result exposes artifact bindings until every immutable write, reread and proof
recheck succeeds. A final receipt is the publication boundary; interrupted partial
files have no accepted receipt. Existing engine names in explicit legacy products
remain retained profiles and never produce schema-v7 actual-cell receipts.

## State, Ownership, and Lifecycle
Actor state contains only Sendable injected dependencies. Each invocation owns its
noncopyable context and all candidates. The Liberty resource owner uses Mutex and
retains original facts until compilation finishes. No locks span I/O or callbacks.

## Failure, Concurrency, and Constraints
Typed host errors preserve input/codec/library/kernel/proof/STA/persistence causes.
Blocked STA diagnostics retain their original reason in the Runtime error and CLI.
Cancellation/deadline/resource outcomes remain distinguishable. Input/output and
parse bounds cover host byte buffers; kernel table payload budgets remain distinct
from RSS measurements. Concurrent actor invocations have independent run contexts;
immutable file collisions fail rather than overwrite.

## Verification and Change Impact
Runtime tests own actual API source/library/netlist/proof/save/reload, cancellation,
digest/schema/library/pin/certificate corruption, failed metrics and partial-save
behavior. CLI and composing host tests own adoption. Portable kernels retain their
separate Native/WASM/Embedded evidence; host I/O and STA are Native-only.

Mapped port bits retain separate p<port>_<bit> identities and one physical net per
mapped net. Constants use TimingDesign v2 binary driver facts. Required numeric and nil slack both require no unconstrained endpoints for that
check kind. Aggregate nil slack
satisfies a demanded setup/hold minimum only when every scenario has relevant
checked static or explicitly excluded endpoints and no relevant unconstrained endpoint; empty/unmeasured coverage
still fails. Dynamic metric requirements remain numeric. The conditional-model
receipt version is defined by [VerifiedArtifacts](../VerifiedArtifacts/DESIGN.md).

Timing exception semantics belong to [PathAnalysis](../../../../TimingEngine/Sources/STAEngine/NativeExecution/PathAnalysis/DESIGN.md).
False paths suppress timing checks only. Functional proof is still mandatory for
all inputs/state. All-excluded timing retains nil numeric slack with explicit
excludedChecks; static and excluded evidence remain distinct.

## Realization Admission

The request explicitly binds a standard-netlist or physical-cell
realization policy. Its host coding value projects to the lower MappedGraph policy,
not to a new startup authority. Mapping inserts exact tie cells when physical
realization is required. Injected mapping output and structural reimport are
independently checked against that policy before proof and publication.
Ordinary Liberty FF/latch startup is unspecified. Declared binary startup demands
are refused; source simulation and binary lowering retain those values. An async
reset pin never implies a reset-before-observation environment assumption.
Structural reimport must reproduce every mapped connection and identity before
any checked proof is constructed. Current Timing requires observed hold tables
for measured hold checks; absence remains unmeasured rather than zero.

## Source-cell operating-condition expansion

Requests explicitly apply each exact source-cell condition to every generated
instance of that cell. Policies bind full mapping-library ArtifactReference, cell,
optional corner and lower PG conditions. Nil operating process scope is source-only
and cannot be joined to STA; an explicit process scope expands conditions in every
declared corner without requiring baseline timing measurement. Optional requested
STA still executes and requires exactly one policy per selected conditional
cell/requested corner.
Callers never guess generated instance IDs. All policies are source-validated before
mapping, including unused cells. Duplicate library/cell/corner keys fail even if
values agree. Foreign references, unknown cells/corners and bad PG conditions fail.
No wildcard/override/fallback exists. Valid unused policies retain validated-unused
outcomes and empty resolved lists.

Mapping/reimport expands to all actual canonical instance IDs, existing `i<index>`
interchange names, cell IDs/names, exact library/corner and checked source outcomes.
Every selected PG/power-down cell requires complete coverage, including injected
mapping outputs. Execution/reload forward identical resolved assumptions to STA.
Every STA library must equal the complete mapping-library reference. Separate
Liberty files for required corners need a separate explicit functional-equivalence
contract outside this sprint. Conditions never restrict binary data/current-state
proof, create startup/reset sequencing, or imply electrical qualification.
Later Physical/CTS instances require checked qualification of their actual mapped
graph; baseline records are not candidate coverage. Physical names/correspondence
remain with their existing owner.

`LogicMappedOperatingConditionsQualifying` exposes checked candidate expansion.
`LogicVerifiedSynthesis` retains the immutable compiled library and private checked
source outcomes. A later run uses its new context to compare the full candidate
library (source, cell/pin IDs, names, directions, functions, state/control and area),
then expands all actual instances/scenarios. It never reuses an expired parse
deadline for source revalidation. No-PG/no-power-down instances have explicit
source-checked empty outcomes and nil policy index. Checked owners are non-Codable;
DTO decoding alone cannot construct them. Fresh artifact reload revalidates source.
Host byte accounting composes the source accountant as defined by
[TechnologyLibraryCompilation](../TechnologyLibraryCompilation/DESIGN.md).

## Functional operating process scope

`LogicOperatingProcessScope` is a declared, Codable cross-source premise with exact
libraries, PDK manifest, process/version, corner IDs and explicit characterization
bindings. It has no SDC, modes, slack requirements or path limit. A timing request
constructor projects these exact existing fields when no separate scope is supplied;
supplying both requires complete equality. Decoding never infers a missing scope.
`constraints.timing` continues to request actual STA and is never bypassed by scope.

Before compilation, the host consumes public PDK manifest decode/validation facts
and the retained Liberty owner's operating-condition facts. It checks process and
version, unique explicit corners and condition selection, manifest Liberty asset
and cross-view associations, full supplied library reference, digest/count,
voltage/Celsius and any required numeric process value. No names, PVT or selected
condition are inferred from a filename, default condition or nominal label. This
is a cross-source premise join; Liberty grammar/evaluation and STA measurement
policy remain lower-owned. No private STA loader is copied or executed.

The same bounded IO and cumulative kernel context cover the extra manifest input,
source checks, workspace and exact comparisons. Public manifest decoding/validation
is an opaque byte-bounded operation; explicit work/storage admission precedes it
and host table/identity checks retain caller table ceilings. It does not establish
an RSS or interrupt-latency guarantee inside the public decoder. Fresh reload
repeats the exact cross-source join; candidate re-expansion consumes the retained
checked synthesis owner under its own context. Raw scope is declaration only,
granting no timing measurement, PVT electrical qualification or release authority.
The original inverter-derived-clock circuit is therefore eligible for functional
baseline proof under explicit scope, while candidate strict STA remains an
independent required consumer gate.
