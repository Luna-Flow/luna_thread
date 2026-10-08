# backend/native API

## Purpose

The package `Luna-Flow/luna_thread/backend/native` is the C foreign function
interface backend. It runs the integer kernels of the C runtime on MoonBit
arrays, submits workflows to the C scheduler, and turns plans into typed native
requests. It builds only for the `native` target and links the C runtime from
its native stubs.

The enumerations and records of this package are read-only outside it: match
on their constructors and read their fields. The request records are built by
the `*_from_plan` functions. The threading model, the memory model and the
derivations behind the kernels are in the
[native backend design](../../design/backend/native.md).

## Importing

Add the package, and `plan`, `shared` and `workflow` for its arguments, to the
`moon.pkg` of a package that builds for the native target:

```moonbit nocheck
import {
  "Luna-Flow/luna_thread/backend/native",
  "Luna-Flow/luna_thread/plan",
  "Luna-Flow/luna_thread/shared",
  "Luna-Flow/luna_thread/workflow",
}

supported_targets = "native"
```

The examples on this page call them as `@native`, `@plan`, `@shared` and
`@workflow`.

## Backend information

### `backend_target`

Returns `Native`.

```mbti
pub fn backend_target() -> @shared.BackendTarget
```

### `default_plan_kind`

Returns `Map`.

```mbti
pub fn default_plan_kind() -> @plan.PlanKind
```

### `package_name`

Returns `"backend/native"`.

```mbti
pub fn package_name() -> String
```

### `supports_openmp`

Returns `true`.

```mbti
pub fn supports_openmp() -> Bool
```

> [!WARNING]
> The value is a constant and does not describe the build. The `moon` build
> compiles the C stubs without OpenMP, so in that build `supports_openmp()`
> returns `true` while the kernels run on the calling thread; see the
> [native backend design](../../design/backend/native.md). The C function
> `luna_thread_runtime_has_openmp` reports the truth but is not bound.

## Kernels

All kernels take a `FixedArray[Int]` of length $n$, a worker count $w$ and a
chunk size $c$, block until they finish, and leave the input unchanged. They
require

$$
n > 0, \qquad 0 < w \le n, \qquad 0 < c \le n, \qquad w \ge \left\lceil \frac{n}{c} \right\rceil
$$

and fail with `InvalidArgument` otherwise. The facade functions of the same
names in the [core API](../core.md) wrap these with optional arguments.

### `execute_map_i32`

Returns a new array with every element doubled, or `Overflow` when some
$2 x_i$ does not fit in 32 bits.

```mbti
pub fn execute_map_i32(FixedArray[Int], Int, Int) -> Result[FixedArray[Int], NativeRequestError]
```

### `execute_reduce_sum_i32`

Returns the sum of the elements, or `0` on any failure.

```mbti
pub fn execute_reduce_sum_i32(FixedArray[Int], Int, Int) -> Int
```

The kernel adds each chunk from the left and then adds the chunk sums from the
left, failing when any of these partial sums overflows.

> [!WARNING]
> Every failure, an invalid argument or an overflow, is returned as `0`. A
> returned non-zero value is the exact sum; `0` is either the sum or a failure.
> With $w = c = 1$ every input longer than one element fails. When you need to
> tell the cases apart, use `execute_scan_sum_i32` and take its last element.

### `execute_scan_sum_i32`

Returns the inclusive prefix sums.

```mbti
pub fn execute_scan_sum_i32(FixedArray[Int], Int, Int) -> Result[FixedArray[Int], NativeRequestError]
```

It fails with `Overflow` when a partial sum overflows.

```moonbit
test "kernels" {
  let input : FixedArray[Int] = [3, 1, 4, 1, 5, 9]
  debug_inspect(
    @native.execute_scan_sum_i32(input, 3, 2),
    content="Ok(<FixedArray: [3, 4, 8, 9, 14, 23]>)",
  )
  assert_eq(@native.execute_reduce_sum_i32(input, 3, 2), 23)
  debug_inspect(@native.execute_map_i32(input, 2, 2), content="Err(InvalidArgument)")
}
```

## Workflows

### `workflow_is_supported`

Returns `true` when `@workflow.validate` finds no issue and the workflow's
policy names the native backend.

```mbti
pub fn workflow_is_supported(@workflow.Workflow) -> Bool
```

### `submit_workflow`

Returns `@workflow.submit(workflow, backend=Native)`: a validated submission
record. It does not run the workflow.

```mbti
pub fn submit_workflow(@workflow.Workflow) -> @workflow.Submission
```

### `WorkflowRuntimeState`

The state of a workflow in the C runtime.

```mbti
pub enum WorkflowRuntimeState {
  Submitted
  Running
  Completed
  Failed
  Rejected
} derive(Eq, @debug.Debug)
```

`Submitted` holds until a worker takes the first node. The runtime never sets
`Rejected`; a rejected submission yields an empty handle instead.

### `WorkflowResult`

A snapshot of a workflow: its state, the runtime status code, the number of
completed nodes and the id of the failed node (`-1` when none failed).

```mbti
pub struct WorkflowResult {
  state : WorkflowRuntimeState
  status : Int
  completed_nodes : Int
  failed_node_id : Int
} derive(Eq, @debug.Debug)
```

`status` is one of the codes in the [architecture guide](../../architecture.md).

### `NativeWorkflowHandle` and `WorkflowHandle`

An opaque pointer to a running workflow in the C runtime, and its MoonBit
wrapper.

```mbti
#external
pub type NativeWorkflowHandle

pub struct WorkflowHandle {
  raw : NativeWorkflowHandle
}
```

### `submit_workflow_async`

Copies a workflow into flat integer arrays and starts it on the C scheduler
with `worker_count` threads from its policy.

```mbti
pub fn submit_workflow_async(@workflow.Workflow) -> Result[WorkflowHandle, NativeRequestError]
```

The workflow is not validated in MoonBit; the C runtime checks it and, when it
rejects the graph, returns an empty handle. The function always returns `Ok`.
Compute nodes are scheduled, but their plans are not executed.

> [!WARNING]
> The C bridge frees the request arrays after the runtime has started, while
> the worker threads still read them. This is a known defect that makes
> programs crash intermittently. Treat this function as experimental.

### `poll_workflow`

Returns a snapshot without waiting.

```mbti
pub fn poll_workflow(WorkflowHandle) -> WorkflowResult
```

### `wait_workflow`

Waits until the workflow is `Completed` or `Failed` and returns the snapshot.

```mbti
pub fn wait_workflow(WorkflowHandle) -> WorkflowResult
```

On an empty handle it returns at once with state `Submitted` and status `7`.
It does not return if the workflow deadlocks.

### `drop_workflow`

Stops and joins the runtime threads and frees the workflow. Call it once per
handle; it does nothing for an empty handle.

```mbti
pub fn drop_workflow(WorkflowHandle) -> Unit
```

## Typed native requests

### `NativeValueType` and `NativeReductionKernel`

The value types and reduction kernels the C runtime implements.

```mbti
pub enum NativeValueType {
  I32
  I64
} derive(Eq, @debug.Debug)

pub enum NativeReductionKernel {
  Sum
  Min
  Max
} derive(Eq, @debug.Debug)
```

### `NativeRequestError`

Why a plan could not become a native request, or why a kernel failed.

```mbti
pub enum NativeRequestError {
  UnsupportedBackend
  UnsupportedMode
  UnsupportedValueType
  UnsupportedReductionKernel
  InvalidArgument
  Overflow
} derive(Eq, @debug.Debug)
```

### `NativeMapRequest`, `NativeReduceRequest` and `NativeScanRequest`

Typed counterparts of the C request structs.

```mbti
pub struct NativeMapRequest {
  input : @shared.NativeBuffer
  output : @shared.NativeBuffer
  element_count : Int
  value_type : NativeValueType
  worker_count : Int
  chunk_size : Int
} derive(Eq, @debug.Debug)

pub struct NativeReduceRequest {
  input : @shared.NativeBuffer
  output : @shared.NativeBuffer
  element_count : Int
  value_type : NativeValueType
  reduction_kernel : NativeReductionKernel
  worker_count : Int
  chunk_size : Int
} derive(Eq, @debug.Debug)

pub struct NativeScanRequest {
  input : @shared.NativeBuffer
  output : @shared.NativeBuffer
  element_count : Int
  value_type : NativeValueType
  reduction_kernel : NativeReductionKernel
  worker_count : Int
  chunk_size : Int
} derive(Eq, @debug.Debug)
```

The `input` and `output` buffers of requests built from plans are
`NativeBuffer::new(0, 0)`: a plan describes the shape of the data, not the
data. No function of the module sends these records to C; they are the
validated description that a future executor will fill with buffers.

### `map_request_from_plan`

Turns a `Map` plan into a `NativeMapRequest`.

```mbti
pub fn map_request_from_plan(@plan.Plan) -> Result[NativeMapRequest, NativeRequestError]
```

It fails with `UnsupportedMode` when the plan is not a `Map` plan, and
otherwise with the error mapped from the first issue of `@plan.validate`:
value type, reduction kernel, backend and mode issues map to the error of the
same name, `MissingReductionKernel` maps to `UnsupportedReductionKernel`, and
the remaining issues map to `InvalidArgument`.

### `reduce_request_from_plan`

Turns a `Reduce` or `MapReduce` plan into a `NativeReduceRequest`, with the same
error rules. The request of a `MapReduce` plan describes only the reduction:
there is no field for the map step, so it is the same request as for a
`Reduce` plan with the same kernel.

```mbti
pub fn reduce_request_from_plan(@plan.Plan) -> Result[NativeReduceRequest, NativeRequestError]
```

### `scan_request_from_plan`

Turns a `Scan` plan into a `NativeScanRequest` whose kernel is `Sum`, with the
same error rules.

```mbti
pub fn scan_request_from_plan(@plan.Plan) -> Result[NativeScanRequest, NativeRequestError]
```

### `map_request_is_valid`, `reduce_request_is_valid` and `scan_request_is_valid`

Check the request fields the C validator also checks: positive element count,
worker count and chunk size, a supported value type, and for scans the `Sum`
kernel.

```mbti
pub fn map_request_is_valid(NativeMapRequest) -> Bool
pub fn reduce_request_is_valid(NativeReduceRequest) -> Bool
pub fn scan_request_is_valid(NativeScanRequest) -> Bool
```

### `map_request_value_type`, `reduce_request_value_type`, `scan_request_value_type`, `reduce_request_kernel` and `scan_request_kernel`

Return the C codes of a request's value type (`0` for `I32`, `1` for `I64`)
and kernel (`0` for `Sum`, `1` for `Min`, `2` for `Max`).

```mbti
pub fn map_request_value_type(NativeMapRequest) -> Int
pub fn reduce_request_value_type(NativeReduceRequest) -> Int
pub fn scan_request_value_type(NativeScanRequest) -> Int
pub fn reduce_request_kernel(NativeReduceRequest) -> Int
pub fn scan_request_kernel(NativeScanRequest) -> Int
```

```moonbit
test "requests from plans" {
  let policy = @shared.make_execution_policy(worker_count=2, chunk_size=4).unwrap()
  let plan = @plan.map_reduce("sum", @plan.i64_type(), 8, @plan.max_reduction(), policy~)
  guard @native.reduce_request_from_plan(plan) is Ok(request) else {
    fail("expected a request")
  }
  assert_true(@native.reduce_request_is_valid(request))
  assert_eq(@native.reduce_request_value_type(request), 1)
  assert_eq(@native.reduce_request_kernel(request), 2)
  let scan = @plan.scan("prefix", @plan.i32_type(), 8, policy~)
  debug_inspect(@native.map_request_from_plan(scan), content="Err(UnsupportedMode)")
}
```

## Raw foreign functions

These `extern "C"` declarations are public so that callers can reach kernels
the typed functions do not wrap, such as the `Int64` kernels and minimum and
maximum reductions. Arrays are borrowed for the duration of the call. Map and
scan return a status code and write into `output`; reductions return the
result, or `0` on failure. The arguments are the input, its length, the worker
count and the chunk size.

> [!WARNING]
> Nothing checks `length` against the arrays. A `length` larger than the input
> or, for map and scan, the output reads or writes past the end of the array.
> Pass `input.length()` and an output at least as long.

### `ffi_execute_map_i32` and `ffi_execute_map_i64`

Double every element into `output`.

```mbti
pub fn ffi_execute_map_i32(FixedArray[Int], Int, Int, Int, FixedArray[Int]) -> Int
pub fn ffi_execute_map_i64(FixedArray[Int64], Int, Int, Int, FixedArray[Int64]) -> Int
```

### `ffi_execute_reduce_sum_i32`, `ffi_execute_reduce_sum_i64`, `ffi_execute_reduce_min_i32`, `ffi_execute_reduce_min_i64`, `ffi_execute_reduce_max_i32` and `ffi_execute_reduce_max_i64`

Return the sum, minimum or maximum of the input.

```mbti
pub fn ffi_execute_reduce_sum_i32(FixedArray[Int], Int, Int, Int) -> Int
pub fn ffi_execute_reduce_sum_i64(FixedArray[Int64], Int, Int, Int) -> Int64
pub fn ffi_execute_reduce_min_i32(FixedArray[Int], Int, Int, Int) -> Int
pub fn ffi_execute_reduce_min_i64(FixedArray[Int64], Int, Int, Int) -> Int64
pub fn ffi_execute_reduce_max_i32(FixedArray[Int], Int, Int, Int) -> Int
pub fn ffi_execute_reduce_max_i64(FixedArray[Int64], Int, Int, Int) -> Int64
```

Minimum and maximum never overflow.

### `ffi_execute_scan_sum_i32` and `ffi_execute_scan_sum_i64`

Write the inclusive prefix sums into `output`.

```mbti
pub fn ffi_execute_scan_sum_i32(FixedArray[Int], Int, Int, Int, FixedArray[Int]) -> Int
pub fn ffi_execute_scan_sum_i64(FixedArray[Int64], Int, Int, Int, FixedArray[Int64]) -> Int
```

### `ffi_submit_workflow_async`

Starts a workflow from flat arrays: worker count; capability ids, kind codes
and count; node ids, kind codes, capability ids (`-1` for none) and count; edge
sources, targets, kind codes and count. Returns a null handle when the runtime
rejects the graph; the C status that explains the rejection is discarded. It
has the request-lifetime defect described under `submit_workflow_async`.

```mbti
pub fn ffi_submit_workflow_async(Int, FixedArray[Int], FixedArray[Int], Int, FixedArray[Int], FixedArray[Int], FixedArray[Int], Int, FixedArray[Int], FixedArray[Int], FixedArray[Int], Int) -> NativeWorkflowHandle
```

### `ffi_workflow_poll_state`, `ffi_workflow_poll_status`, `ffi_workflow_poll_completed_nodes`, `ffi_workflow_poll_failed_node_id`, `ffi_workflow_wait_status` and `ffi_workflow_destroy`

Read one field of a workflow snapshot, wait and return the final status, or
destroy the workflow.

```mbti
pub fn ffi_workflow_poll_state(NativeWorkflowHandle) -> Int
pub fn ffi_workflow_poll_status(NativeWorkflowHandle) -> Int
pub fn ffi_workflow_poll_completed_nodes(NativeWorkflowHandle) -> Int
pub fn ffi_workflow_poll_failed_node_id(NativeWorkflowHandle) -> Int
pub fn ffi_workflow_wait_status(NativeWorkflowHandle) -> Int
pub fn ffi_workflow_destroy(NativeWorkflowHandle) -> Unit
```

On a null handle the poll functions return `0`, `ffi_workflow_wait_status`
returns `7` and `ffi_workflow_destroy` does nothing.

```moonbit
test "raw kernels" {
  let input : FixedArray[Int64] = [5L, -2L, 7L, 0L]
  assert_eq(@native.ffi_execute_reduce_min_i64(input, 4, 2, 2), -2L)
  assert_eq(@native.ffi_execute_reduce_max_i64(input, 4, 2, 2), 7L)
  let output : FixedArray[Int64] = FixedArray::make(4, 0L)
  assert_eq(@native.ffi_execute_scan_sum_i64(input, 4, 2, 2, output), 0)
  debug_inspect(output, content="<FixedArray: [5, 3, 10, 10]>")
}
```

## Equality

### `T::equal`

Structural equality, promoted on `NativeMapRequest`, `NativeReduceRequest`,
`NativeScanRequest`, `NativeReductionKernel`, `NativeRequestError`,
`NativeValueType`, `WorkflowResult` and `WorkflowRuntimeState`. Use `==` and
`!=`. `WorkflowHandle` has no equality.

```mbti
pub fn WorkflowResult::equal(Self, Self) -> Bool
```
