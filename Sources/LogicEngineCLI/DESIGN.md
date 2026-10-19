# LogicEngineCLI

## Purpose and Scope
Headless host execution. Parent: [LogicEngine package](../../DESIGN.md). No children.

## Responsibilities and Boundaries
Decode requests, compose concrete Runtime/store and serialize returned observations.
Own no circuit semantics, certificate authority, STA algorithm or acceptance policy.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | CLI ownership | Headless use | Native host only |
| [Runtime](../LogicEngineRuntime/DESIGN.md) | depends on | Current synthesis/simulation/proof reload | Actual-cell operations | Invalid/old schema fails |

## Architecture
```text
synthesize --request -> Runtime.execute -> receipt + real Verilog + RUP
verify-mapped --request -> checked reload -> functional replay observation
simulate --request -> Runtime.execute -> four-state source/cell observations
```

## Contracts and Invariants
Actual-cell commands require a positive `--maximum-request-bytes` value. The
package-scoped regular-file reader checks this cap before JSON decoding, independently
of the decoded Runtime limits. Missing caps, oversized files and nonregular request
files fail explicitly. Actual-cell commands return zero only after Runtime succeeds. Retired metadata request schemas have no CLI entrypoint. Failed input, library, proof, metric or save
exits nonzero with structured diagnostics. JSON output encoding failure also fails.
Output paths never change artifact meaning. Simulation v4 compiles source or checked actual-cell receipts and returns four-state
event observations. Simulation prints retained explicit assertion violations and exits nonzero when
assessment is failed. A run without a specification remains unassessed.
`verify-simulation` consumes the Runtime checked acceptance reload requirement
with an expected current request and explicit limits; failed or unassessed evidence
cannot return zero from verification. Current commands also include capabilities,
synthesize and verify-mapped.
[Capability discovery](../LogicEngine/DESIGN.md) owns its schema contract.
The lower, legacy-simulate, legacy-synthesize, bounded-equivalence,
unbounded-equivalence and assess-evidence commands are removed.

## Verification and Change Impact
Runtime CLI process tests execute the built binary from source request through
proof, immutable save and verify-mapped reload, plus corrupt input/old schema.
