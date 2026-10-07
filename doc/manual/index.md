# luna_thread

luna_thread is a MoonBit library workspace for parallel execution through the foreign function interface. MoonBit code builds a workflow graph, and a native runtime executes it; a JavaScript compatibility path reaches the same runtime through an N-API addon.

## Realization paths

- MoonBit facade → MoonBit C FFI → C wrapper → C runtime
- MoonBit facade → MoonBit JS FFI → JS wrapper → N-API addon → C runtime

## Packages

- **`facade`** (`luna_thread/`): the root MoonBit package that applications import. See the [API reference](api/facade.md), the [design notes](design/facade.md) and the [tutorial](tutorial/facade.md).
- **`backend`** (`native/`, `js/` and `luna_thread/backend/`): the native C runtime and the Node.js addon that realize the FFI design. See the [API reference](api/backend.md), the [design notes](design/backend.md) and the [tutorial](tutorial/backend.md).

## Specification

The specification is the authoritative design narrative for the workspace: it defines the workflow graph, capabilities, ownership transfer and separation-safe execution that the facade and the backends must realize. The English text is normative; the Chinese text is a strict mirror of it.

[A Normative Specification for a MoonBit Workflow and Parallel FFI Runtime](../attachments/moonbit_parallel_spec/main.typ)
