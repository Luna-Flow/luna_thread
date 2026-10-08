# Architecture

This guide shows how the MoonBit packages, the C runtime and the JavaScript
addon of `luna_thread` fit together, and which integer codes cross the foreign
function interface. The package pages describe each MoonBit package in detail.

## Layers

The specification names two realization paths:

```text
MoonBit facade -> MoonBit C FFI  -> C wrapper  -> C runtime
MoonBit facade -> MoonBit JS FFI -> JS wrapper -> N-API addon -> C runtime
```

The first path exists. The second stops at the MoonBit side: `backend/js`
names the JavaScript target, and the addon in `js/` exports only a
`runtimeName` function.

The MoonBit packages depend on each other without cycles:

| Package | Imports |
| --- | --- |
| `shared` | nothing but the core library |
| `plan` | `shared` |
| `workflow` | `plan`, `shared` |
| `backend/js` | `plan`, `shared` |
| `backend/native` | `plan`, `shared`, `workflow` |
| `core` | `backend/native`, `plan`, `shared`, `workflow` |

- `shared` holds the vocabulary every other package uses: backend targets,
  execution modes, ordering guarantees, execution policies and their
  validation, runtime capability tables, and integer-coded mirrors of the C
  request structs.
- `plan` describes one data-parallel operation over a typed input domain and
  checks it against the v1 subset.
- `workflow` describes a task graph whose nodes may be compute plans or
  synchronisation steps bound to capabilities, and checks its structure.
- `backend/native` translates plans into typed native requests, calls the C
  kernels, and marshals workflows to the C scheduler.
- `core`, the root package, re-exports the common entry points with defaults
  and routes submissions to the native backend.

## The C runtime

The runtime is one C file with one header:

| File | Role |
| --- | --- |
| `native/include/luna_thread_runtime.h` | Public C API: status codes, request structs, workflow types. |
| `native/src/runtime.c` | Kernels, validation and the workflow scheduler. |
| `luna_thread/backend/native/ffi_runtime_impl.c` | The same source, compiled as a MoonBit native stub; it differs only in its `#include` path. |
| `luna_thread/backend/native/ffi_runtime_bridge.c` | `luna_mbt_*` wrappers that turn MoonBit arguments into request structs. |
| `luna_thread/backend/native/ffi_stub.c` | Declarations of the `luna_mbt_*` wrappers. |
| `native/tests/smoke.c` | A C smoke test of the kernels and of their failure statuses. |

The two copies of the runtime must be kept identical by hand.

There are two builds. `moon` compiles the stubs with the system C compiler and
no OpenMP flags, so the `#pragma omp` loops run on the calling thread, while
the workflow scheduler still starts POSIX threads. CMake
(`make native-configure`, `make native-build`) builds `native/` as a static
library with OpenMP when `LUNA_THREAD_ENABLE_OPENMP` is on, together with the
smoke test. The [native backend design](design/backend/native.md) explains both
execution models.

## Codes across the interface

All enumerations cross the C interface as `Int`. The MoonBit side maps them in
`backend/native` (and `shared` for statuses).

### Status codes

| Code | C name | MoonBit `NativeStatus` |
| --- | --- | --- |
| 0 | `LUNA_THREAD_STATUS_OK` | `Ok` |
| 1 | `INVALID_ARGUMENT` | `InvalidArgument` |
| 2 | `UNSUPPORTED_BACKEND` | `UnsupportedBackend` |
| 3 | `UNSUPPORTED_MODE` | `UnsupportedMode` |
| 4 | `UNSUPPORTED_VALUE_TYPE` | `UnsupportedValueType` |
| 5 | `UNSUPPORTED_REDUCTION_KERNEL` | `UnsupportedReductionKernel` |
| 6 | `OVERFLOW` | `Overflow` |
| 7 | `NULL_POINTER` | `NullPointer` |
| 8 | `UNSUPPORTED_RUNTIME_PRIMITIVE` | none |
| 9 | `RUNTIME_BROKEN` | none |
| 10 | `CHANNEL_EMPTY` | none |
| 11 | `CHANNEL_CLOSED` | none |
| 12 | `MUTEX_PROTOCOL_ERROR` | none |
| 13 | `CONDVAR_PROTOCOL_ERROR` | none |
| 14 | `BARRIER_BROKEN` | none |

Codes 8 to 14 come only from the workflow runtime; `WorkflowResult::status`
carries them as raw integers.

### Workflow codes

| Code | Node kind | Capability kind | Edge kind | Runtime state |
| --- | --- | --- | --- | --- |
| 0 | `Compute` | `OwnedBuffer` | `DataDependency` | `Submitted` |
| 1 | `Spawn` | `SharedReadView` | `ControlDependency` | `Running` |
| 2 | `Join` | `AtomicCell` | `OwnershipTransfer` | `Completed` |
| 3 | `Send` | `Mutex` | `SynchronizationDependency` | `Failed` |
| 4 | `Recv` | `Condvar` |  | `Rejected` |
| 5 | `Lock` | `RwLock` |  |  |
| 6 | `Unlock` | `Semaphore` |  |  |
| 7 | `Wait` | `Barrier` |  |  |
| 8 | `Signal` | `Channel` |  |  |
| 9 | `Barrier` | `Opaque` |  |  |
| 10 | `ReadShared` |  |  |  |
| 11 | `WriteShared` |  |  |  |

Value types are `0` for `I32` and `1` for `I64`; reduction kernels are `0` for
`Sum`, `1` for `Min` and `2` for `Max`.

## The JavaScript addon

`js/` is a `node-gyp` project (`make js-install`, `make js-build`) whose C
source registers one function, `runtimeName`, returning
`"luna_thread_addon"`. It does not link the C runtime yet.

## The specification

`doc/attachments/moonbit_parallel_spec/main.typ` is the normative English
specification and `main.zh_CN.typ` its Chinese mirror; `make docs` compiles
both. The specification defines the workflow calculus, ownership transfer,
the ABI layouts and the conformance obligations. The implementation covers the
data model and validation of Part I and the native realization of a subset of
it; the package design pages state which parts. `docs/spec-review-report-zh.md`
records review findings in Chinese.

## Repository layout

| Path | Contents |
| --- | --- |
| `luna_thread/` | The MoonBit module (`moon.mod`) and its packages. |
| `native/` | The C runtime, its header, CMake build and smoke test. |
| `js/` | The Node.js addon scaffold. |
| `doc/` | This manual, its translations and the specification. |
| `scripts/check-env.sh` | Checks the MoonBit, C, Node.js and Typst toolchains. |
| `Makefile` | Shortcuts for checking, building the native runtime and the addon, and compiling the specification. |
