# LogicLowering

## Purpose and Scope
Portable synchronous circuit lowering. Parent: [LogicEngine](../../DESIGN.md).
Children: [ProceduralLowering](ProceduralLowering/DESIGN.md),
[BitExpansion](BitExpansion/DESIGN.md).

## Responsibilities and Boundaries
Own technology-neutral lowering only. Standard Library, CircuiteFoundation Core,
LogicIR and LogicKernelCore are the dependency floor. Host artifact I/O belongs to [Runtime](../LogicEngineRuntime/DESIGN.md).
The legacy execution-graph product is retired.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Portable/host boundary | Public product composition | No metadata execution-graph input |
| [BitExpansion](BitExpansion/DESIGN.md) | child | LogicBitLowering | Word to bit semantics | Binary synthesis profile |
| [ProceduralLowering](ProceduralLowering/DESIGN.md) | child | LogicWordLowering | Ordered RTL to word semantics | Binary synthesis admission |
| [WordGraph](../../../LogicDesign/Sources/LogicIR/WordGraph/DESIGN.md) | depends on | Validated WordLogicDesign | Resolved widths/types | No operator strings |
| [BitGraph](../../../LogicDesign/Sources/LogicIR/BitGraph/DESIGN.md) | depends on | BitLogicBuilder | Validated publication | No technology mapping |

## Architecture
```text
ElaboratedRTL -> LogicWordLowering -> WordLogicDesign -> LogicBitLowering -> BitLogicDesign
                       |
               shared LogicKernelContext
```

## Contracts and Invariants
Public processing boundaries are synchronous Sendable protocols with typed
LogicKernelError. Each run exclusively owns noncopyable workspace and reuses the
caller's context. No Foundation, persistence, library loading or SAT is owned.

## Verification and Change Impact
[LogicBitLoweringTests](../../Tests/LogicBitLoweringTests) owns functional expansion,
state/control, origin and resource tests. Native/WASM/Embedded probes compile,
link and execute the same production source. SourceLoweringTests additionally
compose the public exact-bundle frontend through the actual word/bit kernels and
observe emitted gates, width/sign, controls and failures. Host consumer migration
remains separately tracked in [PROGRESS](../../../PROGRESS.md).
