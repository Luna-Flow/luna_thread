# luna_thread

This manual documents version `0.1.0` of `Luna-Flow/luna_thread` as it stands on
the current branch.

## Overview

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

Version 0.1.0 implements a first, deliberately small subset ("v1"):

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

> [!WARNING]
> Asynchronous workflow runs read freed memory and crash intermittently, and
> some workflows never finish. The [native backend design](design/backend/native.md#known-defects)
> lists the known defects; treat `submit_workflow_async` as experimental.

## Install

```bash
moon add Luna-Flow/luna_thread@0.1.0
```

Then import the facade in the `moon.pkg` of a package that builds for the
native target:

```moonbit nocheck
import {
  "Luna-Flow/luna_thread",
}

supported_targets = "native"
```

The facade is then available as `@luna_thread`. Packages that only build plans
or workflows can import `Luna-Flow/luna_thread/plan` or
`Luna-Flow/luna_thread/workflow` instead and build on every target.

The module uses the `moon.mod` and `moon.pkg` manifest syntax and needs the
MoonBit toolchain 0.10 or later (`moonc` ≥ 0.10). Running the facade needs the
`native` target and a C compiler; the build links the C runtime from the
package's native stubs and uses POSIX threads. Building the standalone C
runtime with OpenMP uses CMake, and the Node.js addon uses `node-gyp`;
`scripts/check-env.sh` checks for all of them.

## Pages

The MoonBit module lives in the `luna_thread/` directory of the repository. It
has six packages, and the root package `Luna-Flow/luna_thread` is documented as
`core`.

| Part | Tutorial | API | Design |
| --- | --- | --- | --- |
| `core`: the facade, `Luna-Flow/luna_thread` | [tutorial](tutorial/core.md) | [API](api/core.md) | [design](design/core.md) |
| `plan`: data-parallel plans and their validation | [tutorial](tutorial/plan.md) | [API](api/plan.md) | [design](design/plan.md) |
| `workflow`: task graphs, capabilities and their validation | [tutorial](tutorial/workflow.md) | [API](api/workflow.md) | [design](design/workflow.md) |
| `shared`: policies, backend targets, status codes, C record mirrors | [tutorial](tutorial/shared.md) | [API](api/shared.md) | [design](design/shared.md) |
| `backend/native`: the C FFI backend, kernels and workflow runtime | [tutorial](tutorial/backend/native.md) | [API](api/backend/native.md) | [design](design/backend/native.md) |
| `backend/js`: the placeholder for the JavaScript backend | [tutorial](tutorial/backend/js.md) | [API](api/backend/js.md) | [design](design/backend/js.md) |

The [architecture guide](architecture.md) spans the packages: it shows how the
MoonBit packages, the C runtime in `native/` and the Node.js addon in `js/`
fit together, and lists the integer codes that cross the foreign function
interface.

## Exported entry points

The facade re-exports the common names; each package page lists the rest.

- Policies: `make_policy`, `default_policy`, `default_backend`,
  `runtime_capabilities`, and in `shared` `ExecutionPolicy`,
  `make_execution_policy` and `validate_policy`
- Plans: `map`, `reduce`, `scan`, `map_reduce`, `validate`, `is_ready`, the
  value types `i32_type` … `opaque_type` and the kernels `sum_reduction`,
  `min_reduction` and `max_reduction`
- Workflows: `workflow`, `compute_task`, `spawn_task`, `join_task`,
  `channel_capability`, `mutex_capability`, `shared_read_capability`,
  `workflow_validate`, `workflow_is_ready` and `submit_workflow`; the full node,
  edge and capability vocabulary is in `workflow`

## Execution

- Direct kernels: `execute_map_i32`, `execute_reduce_sum_i32` and
  `execute_scan_sum_i32` on `FixedArray[Int]`; the `Int64`, minimum and maximum
  kernels are the `ffi_*` functions of `backend/native`
- Asynchronous workflows: `submit_workflow_async`, `poll_workflow`,
  `wait_workflow` and `drop_workflow`
- Plans translate into typed native requests with `map_request_from_plan`,
  `reduce_request_from_plan` and `scan_request_from_plan`; no function executes
  a plan yet

## Where to read next

If you want to run something, start with the [core tutorial](tutorial/core.md):
it doubles, sums and scans an array on the native backend and builds a small
workflow.

- New to the package: read the [core tutorial](tutorial/core.md), then the
  [plan tutorial](tutorial/plan.md) and the [workflow tutorial](tutorial/workflow.md)
  to see what a plan or a workflow means before you build one.
- Using it in a library: keep the [core API](api/core.md), the
  [plan API](api/plan.md) and the [workflow API](api/workflow.md) at hand.
  Write library code against `plan` and `workflow`, which build on every
  target, and leave execution to the application.
- Contributing: read the [architecture guide](architecture.md) and the design
  pages, in particular the [native backend design](design/backend/native.md)
  for the threading and memory model, then the specification above.

## Validation

Run the release checks from the module directory:

```bash
moon -C luna_thread check --target all
moon -C luna_thread test --target native
```

`native/tests/smoke.c`, built by `make native-configure native-build`, checks
the C kernels on their own.
