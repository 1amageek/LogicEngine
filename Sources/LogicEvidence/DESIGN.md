# LogicEvidence

## Purpose and Scope
Passive evidence observations, reports and independent oracle correlation.
Parent: [LogicEngine package](../../DESIGN.md). No children.

## Responsibilities and Boundaries
Own report validation and observation correlation. Execute no simulation,
synthesis, temporal engine or evidence suite. Grant no checked circuit proof,
process qualification or release authorization.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Product composition | Passive host values | No legacy engine dependencies |
| [Public product](../LogicEngine/DESIGN.md) | coordinates with | Capability discovery | Current field/version authority | No suite execution advertisement |
| [Host](../../../Xcircuite/DESIGN.md) | used by | Report decoding and validation | Flow evidence intake | Policy remains Host-owned |

## Architecture
```text
caller-supplied report + independent oracle observations
    -> validate exact case/implementation identities
    -> correlation and explicit mismatches
    -> Host policy intake
```

## Contracts and Invariants
Report schema 1 and passive observation encoding remain unchanged. Corpus outcome
is derived from case mismatches; independent correlation requires complete case,
status and diagnostic coverage with a distinct implementation identity. Report
validation rejects unsupported schema, incomplete identities, duplicate cases and
forged oracle state. Historical observations are not current circuit proof.

## Failure, Concurrency, and Constraints
Immutable Sendable values and synchronous correlation own no process or shared
mutable state. Invalid reports/observations throw LogicEvidenceError. Correlation
mismatches remain explicit values for the consuming policy.

## Verification and Change Impact
[EvidenceTests](../../Tests/LogicEngineTests/EvidenceTests.swift) owns passive
outcome, correlation, forged-state refusal and reviewable mismatch behavior.
Host report intake must remain compatible when these values change.
