# LogicBitLoweringProbeSupport

## Purpose and Scope
Shared portable verification probe. Parent: [LogicEngine](../../DESIGN.md). No children.

## Responsibilities and Boundaries
Exercise the production lowering protocol and independently interpret emitted gates.
This is verification code; it supplies no synthesis implementation or public facade.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [BitExpansion](../LogicLowering/BitExpansion/DESIGN.md) | depends on | LogicBitLowering | Same kernel on three targets | Sequential WASI is not parallel proof |

## Architecture
```text
Native / WASM / Embedded entries -> shared probe -> production lowering
```

## Contracts and Invariants
The same arithmetic/state, existential, cancellation and storage checks execute on
all targets. Only the Embedded entry links its required Unicode data library.

## Verification and Change Impact
[Verifier](../../.verification/logic-bit-expansion/verify-portable.py) owns exact SDK,
compile/link/runtime logs and binary identities. Kernel changes require rebuilding
and running this probe for each claimed target.
