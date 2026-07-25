# LogicEngine Remaining Tasks

Updated: 2026-07-26

LogicEngine is complete for its declared native execution-graph and exact
finite-state proof profile.

## Remaining tasks

| ID | Priority | Owner | Task | Exit criteria |
|---|---|---|---|---|
| LE-1 | P2 | LogicEngine | Expand lowering/execution semantics for hierarchy, wildcard case behavior, wider arithmetic, sequential blocking assignments, multi-event clock sensitivity, and dynamic projections. | Every added semantic has one canonical graph meaning shared by simulation, synthesis, and proof; unsupported cases remain typed blocked; retained differential tests cover success and failure. |
| LE-2 | P2 | LogicEngine and external adapter | Add and correlate an external solver backend when broader temporal proof is required. | A selected solver produces digest-bound raw proof/counterexample artifacts, exact input and executable identity, independent correlation, timeout/cancellation behavior, and ToolQualification-ready observations. |

## External prerequisites

Full SystemVerilog parsing belongs to LogicDesign. Solver trust, flow
orchestration, human review, and release policy remain external.

## Evidence reviewed

- `README.md`
- `DESIGN.md`
- `INTERFACES.md`
- `IMPLEMENTATION_PLAN.md`
- `MILESTONES.md`
- `GOAL_STATUS.md`, especially `Current blockers`
- `Sources` incomplete-implementation marker scan
