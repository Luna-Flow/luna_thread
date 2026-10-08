# shared API

## Purpose

The package `Luna-Flow/luna_thread/shared` holds the vocabulary that every
other package of the module uses: backend targets, execution modes, ordering
guarantees, execution policies and their validation, the declared capabilities
of each backend, native status codes, and integer-coded records that mirror
the C request structs. It has no dependencies besides the core library and
builds on every target.

The enumerations and records of this package are read-only outside it: match
on their constructors and read their fields, but build values with the
functions below. The reasons behind the policy rules and the status-code
mapping are in the [shared design](../design/shared.md).

## Importing

Add the package to your `moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/luna_thread/shared",
}
```

The examples on this page call it as `@shared`.

## Targets, modes and orderings

### `BackendTarget`

The runtime that executes a plan or workflow.

```mbti
pub enum BackendTarget {
  Native
  JavaScript
} derive(Eq, @debug.Debug)
```

### `ExecutionMode`

Whether a submission blocks until it finishes.

```mbti
pub enum ExecutionMode {
  Synchronous
  Asynchronous
} derive(Eq, @debug.Debug)
```

### `OrderingGuarantee`

Whether results must keep the order of the input.

```mbti
pub enum OrderingGuarantee {
  PreserveInputOrder
  RelaxedOrder
} derive(Eq, @debug.Debug)
```

### `native_target`, `javascript_target`, `synchronous_mode`, `asynchronous_mode`, `preserve_input_order` and `relaxed_order`

Return `Native`, `JavaScript`, `Synchronous`, `Asynchronous`,
`PreserveInputOrder` and `RelaxedOrder`.

```mbti
pub fn native_target() -> BackendTarget
pub fn javascript_target() -> BackendTarget
pub fn synchronous_mode() -> ExecutionMode
pub fn asynchronous_mode() -> ExecutionMode
pub fn preserve_input_order() -> OrderingGuarantee
pub fn relaxed_order() -> OrderingGuarantee
```

### `backend_label`

Returns `"native"` or `"javascript"`.

```mbti
pub fn backend_label(BackendTarget) -> String
```

```moonbit
test "targets" {
  inspect(@shared.backend_label(@shared.javascript_target()), content="javascript")
  assert_true(@shared.relaxed_order() is @shared.RelaxedOrder)
}
```

## Execution policies

### `ExecutionPolicy`

How a plan or workflow should run: backend, mode, number of workers, chunk
size and ordering.

```mbti
pub struct ExecutionPolicy {
  backend : BackendTarget
  mode : ExecutionMode
  worker_count : Int
  chunk_size : Int
  ordering : OrderingGuarantee
} derive(Eq, @debug.Debug)
```

### `PolicyIssue` and `PolicyError`

A reason why a policy is outside the v1 subset, and the error that carries the
first such reason.

```mbti
pub enum PolicyIssue {
  WorkerCountMustBePositive(Int)
  ChunkSizeMustBePositive(Int)
  UnsupportedBackendForV1(BackendTarget)
  UnsupportedModeForV1(ExecutionMode)
} derive(Eq, @debug.Debug)

pub struct PolicyError {
  issue : PolicyIssue
} derive(Eq, @debug.Debug)
```

### `make_execution_policy`

Builds a policy and returns the first problem as a `PolicyError`.

```mbti
pub fn make_execution_policy(backend? : BackendTarget, mode? : ExecutionMode, worker_count? : Int, chunk_size? : Int, ordering? : OrderingGuarantee) -> Result[ExecutionPolicy, PolicyError]
```

The defaults are `Native`, `Synchronous`, `1`, `1` and `PreserveInputOrder`.
The checks run in the order `worker_count > 0`, `chunk_size > 0`,
`backend == Native`, `mode == Synchronous`; the ordering is not checked.

### `ExecutionPolicy::new`

Builds a policy like `make_execution_policy` and aborts when it would return an
error, for example for `worker_count=0` or `backend=JavaScript`. Use
`make_execution_policy` when the arguments come from outside the program.

```mbti
pub fn ExecutionPolicy::new(backend? : BackendTarget, mode? : ExecutionMode, worker_count? : Int, chunk_size? : Int, ordering? : OrderingGuarantee) -> Self
```

### `native_policy` and `javascript_policy`

Return the default native policy, and attempt the same for the JavaScript
backend.

```mbti
pub fn native_policy() -> ExecutionPolicy
pub fn javascript_policy() -> ExecutionPolicy
```

`native_policy()` is `make_execution_policy().unwrap()`. `javascript_policy()`
is `make_execution_policy(backend=JavaScript).unwrap()`.

> [!WARNING]
> `javascript_policy()` aborts on every call in v1, because
> `make_execution_policy` rejects the JavaScript backend. It exists so that code
> written for the planned backend compiles; do not call it.

### `validate_policy`

Returns every issue of an existing policy, in the order of the checks above.

```mbti
pub fn validate_policy(ExecutionPolicy) -> Array[PolicyIssue]
```

`ExecutionPolicy` is read-only outside this package, so the functions above
are the only way to obtain one, and each of them either returns a policy that
passes every check or aborts. Outside `shared`, `validate_policy` therefore
always returns `[]`. It exists as a defensive re-check: `@workflow.validate`
calls it on the policy stored in a workflow, and the
[shared design](../design/shared.md) derives why the result is empty.

### `is_parallel`

Returns `true` when the policy asks for more than one worker.

```mbti
pub fn is_parallel(ExecutionPolicy) -> Bool
```

```moonbit
test "policies" {
  let policy = @shared.make_execution_policy(worker_count=4, chunk_size=8).unwrap()
  assert_true(@shared.is_parallel(policy))
  assert_eq(@shared.validate_policy(policy).length(), 0)
  let rejected = @shared.make_execution_policy(backend=@shared.javascript_target())
  debug_inspect(
    rejected,
    content="Err({ issue: UnsupportedBackendForV1(JavaScript) })",
  )
  assert_false(@shared.is_parallel(@shared.native_policy()))
}
```

## Runtime capabilities

### `RuntimeCapabilities`

The features a backend declares.

```mbti
pub struct RuntimeCapabilities {
  backend : BackendTarget
  supports_parallelism : Bool
  supports_async : Bool
  supports_zero_copy_buffers : Bool
} derive(Eq, @debug.Debug)
```

### `RuntimeCapabilities::for_backend`

Returns the declared table of a backend.

```mbti
pub fn RuntimeCapabilities::for_backend(BackendTarget) -> Self
```

| Backend | Parallelism | Async | Zero-copy buffers |
| --- | --- | --- | --- |
| `Native` | `true` | `false` | `false` |
| `JavaScript` | `true` | `true` | `true` |

The table is a fixed declaration, not a probe of the running system. The
native row declares parallelism, but the `moon` build compiles the C runtime
without OpenMP, so the kernels run on one thread there; only the workflow
scheduler starts threads. The JavaScript entries describe the backend the
specification plans; the JavaScript backend executes nothing yet.

## Native status codes

### `NativeStatus`

The status codes 0 to 7 of the C runtime.

```mbti
pub enum NativeStatus {
  Ok
  InvalidArgument
  UnsupportedBackend
  UnsupportedMode
  UnsupportedValueType
  UnsupportedReductionKernel
  Overflow
  NullPointer
} derive(Eq, @debug.Debug)
```

### `native_status_code` and `native_status_from_code`

Convert between `NativeStatus` and its C code.

```mbti
pub fn native_status_code(NativeStatus) -> Int
pub fn native_status_from_code(Int) -> NativeStatus
```

`native_status_code` numbers the constructors 0 to 7 in declaration order.
`native_status_from_code` inverts it on 0 to 7 and maps every other code,
including the workflow statuses 8 to 14, to `InvalidArgument`.

```moonbit
test "status codes" {
  assert_true(@shared.native_status_from_code(6) is @shared.Overflow)
  assert_true(@shared.native_status_from_code(14) is @shared.InvalidArgument)
  for code in 0..<8 {
    let status = @shared.native_status_from_code(code)
    assert_eq(@shared.native_status_code(status), code)
  }
}
```

## Integer-coded native records

These records mirror the C structs `luna_thread_buffer`,
`luna_thread_map_request`, `luna_thread_reduce_request` and
`luna_thread_scan_request` field by field, with enumerations as `Int` codes.
No package of the module consumes them; `backend/native` uses its own typed
records. They store their arguments unchecked.

### `NativeBuffer`

A pointer, as an `Int`, and a length.

```mbti
pub struct NativeBuffer {
  ptr : Int
  length : Int
} derive(Eq, @debug.Debug)
pub fn NativeBuffer::new(Int, Int) -> Self
pub fn NativeBuffer::ptr(Self) -> Int
pub fn NativeBuffer::length(Self) -> Int
```

### `NativeMapRequest`

Input and output buffers, element count, value type code, worker count and
chunk size.

```mbti
pub struct NativeMapRequest {
  input : NativeBuffer
  output : NativeBuffer
  element_count : Int
  value_type : Int
  worker_count : Int
  chunk_size : Int
} derive(Eq, @debug.Debug)
pub fn NativeMapRequest::new(NativeBuffer, NativeBuffer, Int, Int, Int, Int) -> Self
pub fn NativeMapRequest::input(Self) -> NativeBuffer
pub fn NativeMapRequest::output(Self) -> NativeBuffer
pub fn NativeMapRequest::element_count(Self) -> Int
pub fn NativeMapRequest::value_type(Self) -> Int
pub fn NativeMapRequest::worker_count(Self) -> Int
pub fn NativeMapRequest::chunk_size(Self) -> Int
```

The constructor takes the fields in declaration order.

### `NativeReduceRequest` and `NativeScanRequest`

The same fields as `NativeMapRequest` plus a reduction kernel code, placed
after the value type.

```mbti
pub struct NativeReduceRequest {
  input : NativeBuffer
  output : NativeBuffer
  element_count : Int
  value_type : Int
  reduction_kernel : Int
  worker_count : Int
  chunk_size : Int
} derive(Eq, @debug.Debug)
pub fn NativeReduceRequest::new(NativeBuffer, NativeBuffer, Int, Int, Int, Int, Int) -> Self
pub fn NativeReduceRequest::input(Self) -> NativeBuffer
pub fn NativeReduceRequest::output(Self) -> NativeBuffer
pub fn NativeReduceRequest::element_count(Self) -> Int
pub fn NativeReduceRequest::value_type(Self) -> Int
pub fn NativeReduceRequest::reduction_kernel(Self) -> Int
pub fn NativeReduceRequest::worker_count(Self) -> Int
pub fn NativeReduceRequest::chunk_size(Self) -> Int

pub struct NativeScanRequest {
  input : NativeBuffer
  output : NativeBuffer
  element_count : Int
  value_type : Int
  reduction_kernel : Int
  worker_count : Int
  chunk_size : Int
} derive(Eq, @debug.Debug)
pub fn NativeScanRequest::new(NativeBuffer, NativeBuffer, Int, Int, Int, Int, Int) -> Self
pub fn NativeScanRequest::input(Self) -> NativeBuffer
pub fn NativeScanRequest::output(Self) -> NativeBuffer
pub fn NativeScanRequest::element_count(Self) -> Int
pub fn NativeScanRequest::value_type(Self) -> Int
pub fn NativeScanRequest::reduction_kernel(Self) -> Int
pub fn NativeScanRequest::worker_count(Self) -> Int
pub fn NativeScanRequest::chunk_size(Self) -> Int
```

```moonbit
test "native records" {
  let buffer = @shared.NativeBuffer::new(0, 4)
  let request = @shared.NativeReduceRequest::new(buffer, buffer, 4, 0, 1, 2, 2)
  assert_eq(request.reduction_kernel(), 1)
  assert_eq(request.input().length(), 4)
}
```

## Equality and package information

### `T::equal`

Structural equality, promoted on every type of the package:
`BackendTarget`, `ExecutionMode`, `ExecutionPolicy`, `NativeBuffer`,
`NativeMapRequest`, `NativeReduceRequest`, `NativeScanRequest`,
`NativeStatus`, `OrderingGuarantee`, `PolicyError`, `PolicyIssue` and
`RuntimeCapabilities`. Use `==` and `!=`.

```mbti
pub fn ExecutionPolicy::equal(Self, Self) -> Bool
```

### `package_name`

Returns `"shared"`.

```mbti
pub fn package_name() -> String
```
