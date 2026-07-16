# LogicEngine Implementation Instructions

## Goal

Implement functional logic simulation and logic synthesis over logicdesign.

## Required boundaries

- Keep public interfaces protocol-first.
- Use one primary type per Swift file.
- Keep code, comments and documentation comments in English.
- Use typed errors and never use `try?`.
- Do not add `@unchecked Sendable`, `DispatchQueue` or `EventLoopFuture`.
- Use actor only for ordered or suspending state; use Mutex for short in-memory critical sections.
- Do not import Xcircuite or circuit-studio.
- Preserve typed domain requests/results and the artifact provenance contract.
- Treat unavailable semantics as blocked, not passed.
- Keep native and external implementations behind the same protocol.

## Before implementation

Read README.md, DESIGN.md, INTERFACES.md and IMPLEMENTATION_PLAN.md completely.

## Definition of done

Build, timeout-bounded tests, fixtures, structured diagnostics, CLI reproducibility, direct protocol conformance, Xcircuite composition coverage, and qualification scope are all required.
