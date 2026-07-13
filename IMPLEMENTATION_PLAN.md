# LogicEngine Implementation Plan

## Order and status

1. Boundary and evidence baseline — complete for the current audit.
2. Canonical execution contract and deterministic RTL lowering — complete for
   the retained native lowering profile.
3. Native RTL execution semantics — complete for the retained native profile;
   concat/slice/plain case/scalar/vector logical operations and logical NOT,
   comparisons, unsigned and signed arithmetic, division/modulo, signed
   literals, synchronous/asynchronous reset paths, sampled non-blocking updates,
   level-sensitive latches, structural driver/cycle validation, and explicit
   blocked boundaries are covered.
4. Synthesis correctness and acceptance — complete for native mapping, typed
   request, mapped-proof handoff, evidence persistence, and acceptance gating;
   mapped results still remain `pendingEquivalence` until a downstream proof
   stage resolves the request.
5. Verification and oracle correlation — complete for the LogicEngine native
   bounded and exhaustive finite-state profiles, with independent oracle
   correlation and digest-bound reports/certificates. General RTL/DFT solver
   execution remains external.
6. Xcircuite execution and human-in-the-loop — complete for the package-owned
   typed adapters, review/audit artifact contracts, equivalence resume inputs,
   and qualification report integrity boundaries. Orchestration and approval
   policy remain Xcircuite-owned.
7. Process qualification and release eligibility — complete for the retained
   local native fixture process scope with PDK/input/output digest evidence and
   separate human approval; foundry-specific qualification remains separate.
8. Qualified unbounded temporal equivalence — complete for exact exhaustive
   two-state/four-state combinational, DFF, and latch execution graphs with
   limit, timeout, counterexample, unsupported, certificate, and qualification
   evidence paths. Arbitrary SystemVerilog and DFT proof views remain outside
   this native scope.

## Current implementation slice

- Expand native RTL execution without silently changing semantics: plain case,
  scalar/vector logical operations and logical NOT, comparisons, unsigned and
  signed arithmetic, division/modulo, signed literals, synchronous/asynchronous
  reset, non-blocking scheduling, level-sensitive latches, vector projections,
  exact unknown propagation, structural topology validation, and cancellation
  records.
- Keep wildcard case, hierarchy, sequential blocking assignments, unsupported
  multi-event sensitivity, unsupported widths, and dynamic projections as
  structured blocked boundaries until their rules are modeled.

The first implementation slice is retained in `Tests/LogicEngineTests/Fixtures`
and exercised through the typed API, CLI capability surface, and Xcircuite stage
adapters.

## Completion gates

- Public APIs remain protocol-first and Sendable.
- Every unsupported semantic produces a structured blocked result.
- Native and external backends produce the same result schema.
- No UI type enters a public contract.
- No result claims foundry qualification without process-scoped oracle evidence.
- Qualification reports are persisted as digest-bearing JSON artifacts and are
  revalidated before a runtime stage can use them.
- Xcircuite can execute and persist the native equivalence handoff without
  circuit-studio; a valid persisted equivalence result can be resumed without
  rerunning proof. Native exhaustive proof and local fixture release evidence
  are independently reproducible; external solver trust and production repair
  loops remain platform-level gates.
