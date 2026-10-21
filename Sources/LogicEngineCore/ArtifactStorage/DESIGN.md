# ArtifactStorage

## Purpose and Scope
Exact host artifact bytes. Parent: [Core](../DESIGN.md). No children.

## Responsibilities and Boundaries
Own content identity/materialization binding, digest-verified reads and immutable
atomic per-file writes. Own no graph meaning, multi-file completion or release gate.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Core](../DESIGN.md) | parent | Host values | Exact availability | No portable imports |

## Architecture
```text
binding -> contained local file -> bounded exact read -> size/SHA-256 check
bytes -> atomic create-only file -> binding -> caller-owned completion receipt
```

## Contracts and Invariants
Only regular files are admitted, using a nonblocking open and descriptor inspection
before allocation. Filesystem reads stop at the declared byte count plus one detection byte, even if
the file grows. Runtime pre-admits the declared count against its host budget.
Oversize/short/digest-mismatched inputs fail. Injected stores must fulfill exact
read ownership; Runtime independently validates their returned bytes. Existing
same-content writes are idempotent; bounded existing-file comparison rejects
different-content collisions without overwriting. The package-scoped reader also
admits CLI request bytes against an explicit caller-selected cap before decoding.

## State, Ownership, and Lifecycle
Filesystem handles are invocation-owned and explicitly closed. Store values hold
immutable root configuration. No locks surround I/O. Multi-file publication belongs
to Runtime's final receipt; individual files alone do not establish completion.

## Failure, Concurrency, and Constraints
Read/write/close failures retain the host failure category. Existing root containment
and symlink rejection remain in force. Declared byte count must fit host addressing.

## Verification and Change Impact
LogicEngineTests owns filesystem boundary/collision tests. Runtime tests own corrupt
inputs, partial saves and receipt publication. No general filesystem sandbox claim.

## Controlled Read Capability

The controlled host reload described by
[VerifiedArtifacts](../../LogicEngineRuntime/VerifiedArtifacts/DESIGN.md#controlled-reload)
uses an opt-in capability, separate from legacy `LogicArtifactStoring.read`.
The current Native host resource, cancellation, explicit-grant and last-owner
checks are qualified by the focused evidence recorded in that owning design:

```swift
public protocol LogicArtifactControlledReading: Sendable {
    func readControlled(
        _ artifact: LogicArtifactBinding,
        budget: ArtifactAccessBudget,
        control: any ArtifactSourceControl
    ) async throws -> (value: Data, retention: LogicArtifactReadRetention)
}
```

Reuse the existing CF source control requirements, including read/hash/page
work and owned/temporary/open-resource extents; no guessed descriptor-to-byte
conversion is introduced. Runtime adapts its original arbitrary-error accountant
and records the original cause before throwing a typed CF control failure. Core
does not import Runtime or portable kernel semantics.
FileSystemLogicArtifactStore implements the capability with the existing
CircuiteFoundation `ArtifactSourceDiscovering.discover(_:control:)` operation
on its exact workspace/output-root capability. Its PN2.0 source owner already
admits descriptor, page/container, read/hash work and accounted contiguous-copy
extents, and closes before success. Compare the resulting complete reference
to the ORIGINAL expected reference; discovery never replaces that input identity.
Missing capability refuses and never falls back to the bare legacy method.

The full retained Data copy is admitted before conversion while the exact
controlled discovered-source pages remain alive. Use their accounted contiguous
borrow when needed; page/container/descriptor leases follow the original CF
owners and finish after the copy. The returned anchor owns the final Data
payload admission, not discarded page/copy scratch. All shared Data copies
require that anchor. Declared bytes remain subject to Runtime cumulative input
limits; source-operation budgets are not new invocation budgets. Opaque Foundation/crypto internal workspace remains distinct from this
code's materialized payloads.

Read and close failures preserve the original CF composite causes. CF owns
checked descriptor cleanup on every path; Runtime does not invent a retryable
FD owner after that operation has returned. No successful value is published
when close fails, and no stringification replaces the original error. The CF
typed-control adapter records the original arbitrary external cause before
throwing a typed control sentinel; the Runtime boundary rethrows that cause.
Source cleanup runs even after cancellation/admission failure. The operation retains the root descriptor admission until its asynchronous
termination completes. Root close and primary failures are combined without
replacing either cause. A root-close failure retains its descriptor admission
through the final failure copy; it does not claim that CF exposes close retry. No cancellation check can bypass that close.
Legacy root containment, regular-file, bounded-length, SHA-256 and immutable
write contracts remain unchanged; this does not add hostile-filesystem or RSS
claims. Focused verification belongs to the Runtime controlled-reload suite and
Core artifact tests, including no-capability refusal, page-bound cancellation,
short/growing/tampered input, close failure, reuse and final-anchor refund.

Controlled reads also accept the existing absolute `logic-local-file-system`
bindings only after matching their exact UTF-8 segments against an immutable
normalized workspace/output-root prefix captured by the store initializer. This
configuration is caller-owned, like the original stored root URLs. Each read
admits and checks the relative-segment conversion before construction and uses
the selected existing root capability; it never opens an unrestricted filesystem
root. Ambiguous symlink/alias spellings that the controlled owner cannot attest
fail explicitly rather than fall through to legacy reading.

### Explicit additional controlled roots

`LogicArtifactReadRoot(rootID:directoryURL:)` is immutable caller-owned grant
configuration prepared before controlled invocation accounting. It stores only a
validated file URL and normalized path components, not an open descriptor.
`FileSystemLogicArtifactStore` has a distinct throwing initializer requiring the
explicit `controlledReadRoots` argument. Duplicate/reserved IDs refuse during
configuration; the existing nonthrowing initializer and old read/write behavior
remain unchanged. An unknown direct root ID refuses. Absolute legacy availability
may be translated only under the exact workspace/output/additional-grant prefix.
No untrusted binding grants a directory, and no unrestricted root is synthesized.
Each operation opens/closes its own CF capability under the selected grant and
retains the configured value through that operation. Root traversal and symlinks
remain governed by the existing CF owner, not by prefix matching alone.
