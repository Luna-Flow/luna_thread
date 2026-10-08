# luna_thread

`luna_thread` lets MoonBit programs describe parallel work as data and run part
of it on a native C runtime. A program builds **plans** (map, reduce, scan and
map-reduce over a typed input domain) and **workflows** (task graphs whose
nodes use capabilities such as channels, mutexes and barriers), validates them
in MoonBit, and executes integer kernels and workflow graphs through the C
foreign function interface. A JavaScript path through a Node.js addon is
scaffolded but does not execute anything yet.

The repository also holds the normative specification that the implementation
is moving towards. This manual describes what the current branch implements;
where the code is narrower than the specification, the pages say so.

[A Normative Specification for a MoonBit Workflow and Parallel FFI Runtime](../attachments/moonbit_parallel_spec/main.typ)

## Status

The module is at version 0.1.0 and implements a first, deliberately small
subset ("v1"):

- Plans and workflows are validated in MoonBit, and only the native backend in
  synchronous mode passes validation.
- The executable kernels are element-wise doubling, sum, minimum and maximum
  reductions, and inclusive prefix sums over `Int` and `Int64`. The facade
  exposes the `Int` versions of doubling, sum and prefix sum.
- Workflow graphs run on a pthread scheduler in C that executes the
  synchronisation protocol of each node. Compute nodes are scheduled but do not
  yet run their plan.
- The facade and `backend/native` build only for the `native` target; `plan`,
  `shared`, `workflow` and `backend/js` build for every target.

## Packages

The MoonBit module lives in the `luna_thread/` directory of the repository; its
root package is documented as `core`.

| Package | Import path | Contents | Pages |
| --- | --- | --- | --- |
| `core` | `Luna-Flow/luna_thread` | The facade: policies, plan and workflow builders, direct execution and asynchronous workflows. | [API](api/core.md) · [Tutorial](tutorial/core.md) · [Design](design/core.md) |
| `plan` | `Luna-Flow/luna_thread/plan` | Backend-independent data-parallel plans and their validation. | [API](api/plan.md) · [Tutorial](tutorial/plan.md) · [Design](design/plan.md) |
| `workflow` | `Luna-Flow/luna_thread/workflow` | Task graphs with capabilities, their validation and submission records. | [API](api/workflow.md) · [Tutorial](tutorial/workflow.md) · [Design](design/workflow.md) |
| `shared` | `Luna-Flow/luna_thread/shared` | Execution policies, backend targets, runtime capabilities and the integer-coded FFI records. | [API](api/shared.md) · [Tutorial](tutorial/shared.md) · [Design](design/shared.md) |
| `backend/native` | `Luna-Flow/luna_thread/backend/native` | The C FFI backend: kernels, the workflow runtime and typed native requests. | [API](api/backend/native.md) · [Tutorial](tutorial/backend/native.md) · [Design](design/backend/native.md) |
| `backend/js` | `Luna-Flow/luna_thread/backend/js` | The placeholder for the JavaScript backend. | [API](api/backend/js.md) · [Tutorial](tutorial/backend/js.md) · [Design](design/backend/js.md) |

The C runtime in `native/`, its copy compiled as a MoonBit native stub, and the
Node.js addon in `js/` are not MoonBit packages; the
[architecture guide](architecture.md) describes them and how the layers fit
together.

## Reading paths

If you want to run something, start with the [core tutorial](tutorial/core.md):
it doubles, sums and scans an array on the native backend and submits a small
workflow. To understand what a plan or a workflow means before you build one,
read the [plan tutorial](tutorial/plan.md) and the
[workflow tutorial](tutorial/workflow.md). If you already use the library, the
API pages list every public name, starting with the [core API](api/core.md).
Contributors should read the [architecture guide](architecture.md) and the
design pages, in particular the [native backend design](design/backend/native.md)
for the threading and memory model, then the specification above.

## Toolchain

The module uses the `moon.mod` and `moon.pkg` manifest syntax and needs MoonBit
`moonc` 0.10 or later. Running the facade needs the `native` target and a C
compiler; the build links the C runtime from the package's native stubs and
uses POSIX threads. Building the standalone C runtime with OpenMP uses CMake,
and the Node.js addon uses `node-gyp`; `scripts/check-env.sh` checks for all of
them.

## Installation

Add the module to your project:

```text
moon add Luna-Flow/luna_thread@0.1.0
```

Import the facade in the `moon.pkg` of a package that builds for the native
target:

```text
import {
  "Luna-Flow/luna_thread",
}

supported_targets = "native"
```

The facade is then available as `@luna_thread`. Packages that only build plans
or workflows can import `Luna-Flow/luna_thread/plan` or
`Luna-Flow/luna_thread/workflow` on any target.
