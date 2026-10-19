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
