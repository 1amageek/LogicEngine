# LogicEngine

Typed logic kernels and host source-to-actual-cell execution over LogicDesign.

## Public source prerequisite

This source snapshot publishes the selected LogicEngine implementation required by
PhysicalDesignEngine. Its qualification scope is the Native host source/PVT/PG,
strict STA and checked persistence paths identified in [DESIGN.md](DESIGN.md).
It does not claim complete physical-design, process, full SystemVerilog, DFT,
or platform release qualification. Historical evidence retains its original scope.

This is a source migration from the earlier public metadata execution API.
The old Core graph/document request types and legacy lowering, bounded-trace,
exhaustive-equivalence and executable evidence-suite commands are retired.
Callers must use current Runtime requests with original source bundles, explicit
limits and actual libraries where required. Old receipts are not upgraded into
checked actual-cell proof. `LogicEngineRuntime` and `LogicProof` are additional
public products; preserved product names do not imply old API compatibility.

## Products

| Product | Responsibility |
|---|---|
| `LogicLowering` | Portable typed word and bit lowering |
| `LogicSimulation` | Portable four-state source and actual-cell events |
| `LogicSynthesis` | Actual-cell mapping and candidate optimization |
| `LogicProof` | Independent CNF/RUP checking and functional circuit equivalence |
| `LogicEngineCore` | Bounded host artifact reads, identities and typed failures |
| `LogicEngineRuntime` | Source/library preparation, host execution, required STA and checked reload |
| `LogicEvidence` | Passive evidence reports and oracle-correlation values |
| `LogicEngine` | Direct public reexports and versioned capability discovery |
| `logic-engine` | Native host CLI |

[Runtime](Sources/LogicEngineRuntime/DESIGN.md) composes portable kernels directly.
It publishes an accepted receipt only after immutable artifact writes, rereads and
proof checks complete. Functional proof, required strict STA, assertion acceptance
and release authorization remain separate contracts. Unsupported semantics,
resource exhaustion and cancellation cannot become completed results.

## Dependencies and use

The manifest selects exact public HTTPS revisions of CircuiteFoundation,
LogicDesign, TimingEngine and PDKKit. Their current identities and qualification
boundary are owned by [the package design](DESIGN.md#current-simulation-parameter-dependency-alignment).
The historical pin-only successor to public `3b3db10ddd8aa4cfb0e938da6644999f1feba5bb` aligned
TimingEngine `bc88162612c089c66d1a4022230d23958a7738c0` and PDKKit
`2c35305fd943174b98009368cf0481f3b308718f`, preserving every implementation,
test and resource byte. Existing runtime receipts keep their original graph;
final Physical integration owns the new consumer execution.
No local path, edited dependency or availability mirror is a release dependency.
The Native host baseline is Swift 6.4 and macOS 27.

```sh
swift build --product logic-engine --jobs 2
swift run logic-engine capabilities
swift run logic-engine synthesize --request request.json --maximum-request-bytes 1048576 --root project
```

The current commands are `simulate`, `verify-simulation`, `synthesize` and
`verify-mapped`; each request command requires an explicit positive
`--maximum-request-bytes`. Use the request and loader protocols documented in
[ActualCellExecution](Sources/LogicEngineRuntime/ActualCellExecution/DESIGN.md),
[VerifiedArtifacts](Sources/LogicEngineRuntime/VerifiedArtifacts/DESIGN.md) and
[EventExecution](Sources/LogicEngineRuntime/EventExecution/DESIGN.md).
Capability schema and request schemas must be checked independently.

The focused consuming fixtures are
[OperatingProcessScopeTests](Tests/LogicRuntimeTests/OperatingProcessScopeTests.swift)
and [ActualCellOperatingConditionTests](Tests/LogicRuntimeTests/ActualCellOperatingConditionTests.swift).
They exercise source-selected functional premises, candidate qualification,
strict native STA, cancellation/resource refusal and exact checked reload.
The original prerequisite graph executed all ten tests with zero skips on Swift 6.4.0
and the macOS 27 SDK. Execution evidence is recorded outside the distributed
source tree; the focused result is not whole-platform or process qualification.

## License

Owned source and documentation are available under [MIT](LICENSE). Dependencies,
external tools and model/PDK inputs retain their own licenses and notices; this
license does not relicense third-party materials.


## Current simulation-parameter dependency floor

The [current dependency contract](DESIGN.md#current-simulation-parameter-dependency-alignment)
selects PDKKit `1bd686f8a4b47a90ef136b5f7dbcca7390971b8e`, TimingEngine `812036ecfcbbefdb784be344c8a1087c7eec8766`.
Its CoreSpice source is `82eb35e8bc57402880db3529c8a1dc2045349d87`; CF `5f132c58` and SDK `1.2.0` remain fixed.
Source behavior is retained; final Physical integration owns new consumer execution.


## Controlled reload qualification

The [controlled public-floor contract](DESIGN.md#controlled-reload-on-the-stable-public-floor) owns the exact current dependency selectors and finite qualification scope. The additive API retains the original accountant, proof and STA authority; existing CLI commands keep their legacy contract. On the locked public graph, the final Native host API/CLI run passed 19 declarations / 31 expanded cases with zero skips. Unchanged prior 32 declarations / 32 cases compose to 51 distinct declarations / 63 cases; this is not an all-fresh or whole-Logic qualification. The sole review finding has a genuine RED and closed targeted recheck.
