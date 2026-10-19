# LogicEngine Implementation Plan

## Authority

[DESIGN.md](DESIGN.md) and its component contracts define current processing.
Workspace PROGRESS.md is the sole completion ledger. [Legacy retirement](DESIGN.md#legacy-api-retirement)
records the approved public compatibility break; metadata engines, bounded/finite-
state temporal APIs and executable evidence suites are no longer implementation work.

## Current execution

Portable word/bit lowering, four-state simulation, actual-cell mapping and
independent checked RUP retain their existing profiles. Runtime composes exact
source/library inputs, explicit limits, STA, immutable publication and checked
reload. Host/RTL migration uses these original inputs or canonical typed structural
inspection; historical metadata is never converted into checked proof authority.

## Completion gates

- Preserve current protocol-first Sendable APIs and typed failure contracts.
- Verify the affected current Native API/CLI success and refusal paths.
- Preserve immutable artifact identity, exact inputs and checked reload.
- Retain passive evidence report validation and independent oracle correlation.
- Remove obsolete Core metadata only after all production callers migrate.
- Reuse portable behavioral evidence only while its source and premises are unchanged.
- Keep process qualification, release eligibility and Host policy with their owners.
