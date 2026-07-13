# LogicEngine Design

## Purpose

Functional logic simulation and logic synthesis over LogicDesign.

## Responsibility boundary

This package owns the schemas and engine protocols listed in its public products. It must remain usable without UI state and without the Xcircuite runtime.

## Non-responsibilities

- Owning canonical RTL or gate IR
- General SystemVerilog/DFT formal solver orchestration
- Physical placement

## Dependency direction

```text
CircuiteFoundation artifact/evidence contract
                 ↓
LogicEngine Foundation-native typed requests/results
                 ↓
native or external-tool backends
                 ↓
Xcircuite compatibility boundary and stage execution
                 ↓
DesignFlowKernel and .xcircuite artifacts
```

Backends may depend on lower-level data packages. This package must never import
`Xcircuite` or `circuit-studio`. Flow and project storage are supplied by
`DesignFlowKernel` and the injected Xcircuite workspace store; they are not
part of the Foundation-native public contract.

## Trust model

Kernel availability, corpus validation, oracle correlation, process-scoped qualification and release approval are distinct states. The package reports capability and evidence; Xcircuite and ToolQualification apply flow policy.

The native exhaustive temporal engine is part of the LogicEngine execution
profile. It proves the complete finite transition relation of the declared
execution graph in a two-state or four-state domain, subject to explicit state,
transition, and timeout limits. It is intentionally separate from the bounded
trace engine and does not claim arbitrary RTL, DFT, or symbolic theorem-proving
coverage.

## Artifact requirements

All outputs are immutable run artifacts with format, digest, producer metadata and the input design/PDK revision needed to reproduce the result.
