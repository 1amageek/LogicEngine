# LogicWordLoweringEmbeddedPortabilityProbe

## Purpose and Scope
Verification executable entry. Parent: [LogicEngine](../../DESIGN.md). No children.

## Responsibilities and Boundaries
Invoke the shared typed word-lowering probe and report success only after it returns.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Probe support](../LogicWordLoweringProbeSupport/DESIGN.md) | depends on | WordLoweringContractProbe.exercise | Shared actual kernel checks | Matching Embedded SDK and Unicode library |

## Architecture
```text
@main -> shared probe -> success marker / process failure
```

## Contracts and Invariants
A thrown probe error terminates the process; it cannot print a success marker.
The entry owns no mutable shared state or domain algorithm. Its source-elaboration
debug profile provisions a 4 MiB WASM linear-memory stack, inherited from the
qualified lower frontend profile. Runtime verification also provisions Node's
4096 KiB host stack. Default-stack portability is not claimed.

## Verification and Change Impact
The [portable verifier](../../.verification/logic-atomic-lowering/verify-portable.py)
checks process status, marker and artifact digest for this exact product.
