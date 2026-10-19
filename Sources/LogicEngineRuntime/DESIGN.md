# LogicEngineRuntime

## Purpose and Scope

Host composition for logic execution. Parent: [LogicEngine](../../DESIGN.md).
Child: [TechnologyLibraryCompilation](TechnologyLibraryCompilation/DESIGN.md).
Children also include [ActualCellExecution](ActualCellExecution/DESIGN.md) and
[VerifiedArtifacts](VerifiedArtifacts/DESIGN.md), owning synthesis orchestration and
checked persistence/reload respectively. [EventExecution](EventExecution/DESIGN.md)
owns host four-state execution.

## Responsibilities and Boundaries

Own host library preparation from TimingCore-owned facts and verified content.
Portable meaning belongs to LogicIR and budgets/control to LogicKernelCore. Own
no grammar, gate evaluator, solver, mapper, generic Engine wrapper or release gate.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LogicEngine](../../DESIGN.md) | parent | Host/kernel separation | Product composition | No new facade |
| [TechnologyLibraryCompilation](TechnologyLibraryCompilation/DESIGN.md) | child | Library compiler | Source facts to actual cells | Functional admission only |
| [LogicIR](../../../LogicDesign/Sources/LogicIR/DESIGN.md) | depends on | Validated builders/values | Portable outputs | No host dependency enters IR |
| [TimingCore](../../../TimingEngine/Sources/TimingCore/DESIGN.md) | depends on | Owned source facts | Sole parser | Timing abstractions are not cell meaning |

## Architecture

```text
TimingCore OwnedLibertySource -> identity verification / library compilation
  -> LogicIR library + per-cell outcomes -> mapped simulation / proof / mapper
```

## Contracts and Invariants

The functional operating process scope and optional timing measurement are distinct
contracts owned by [ActualCellExecution](ActualCellExecution/DESIGN.md). A verified
functional source join never substitutes for a candidate's required strict STA.

Consume original facts through their public contract. Unsupported cells receive
explicit reasons. Crypto/TimingCore dependencies stay in host targets. Compilation
uses the caller's cumulative context and performs no filesystem I/O.

TechnologyLibraryCompilation owns source normal-power admission; ActualCellExecution
owns policy expansion and VerifiedArtifacts owns checked replay. These host premises
do not change portable truth/proof meaning or grant electrical qualification.

## Verification and Change Impact

LogicLibraryCompilationTests own function/pin/state binding and negative admission.
Host API/CLI tests verify dependency adoption and duplicate-interpreter retirement.
This target has Native evidence; LogicIR separately owns three-target evidence.
