# backend/native tutorial

This tutorial shows you how to call the native backend directly: run the typed
kernels, reach the `Int64` and minimum and maximum kernels through the raw
foreign functions, turn plans into native requests, and run a workflow on the
C scheduler.

## Quick start

Import the backend from a package that builds for the native target:

```text
import {
  "Luna-Flow/luna_thread/backend/native",
}

supported_targets = "native"
```

Compute prefix sums with three workers and chunks of two:

```moonbit
test "native quick start" {
  let input : FixedArray[Int] = [2, 4, 6, 8, 10, 12]
  debug_inspect(
    @native.execute_scan_sum_i32(input, 3, 2),
    content="Ok(<FixedArray: [2, 6, 12, 20, 30, 42]>)",
  )
}
```

## Everyday tasks

### Find the minimum and maximum of `Int64` data

The raw functions take the length explicitly and return the result directly:

```moonbit
test "min and max" {
  let samples : FixedArray[Int64] = [12L, -7L, 40L, 3L, 0L, 25L]
  let n = samples.length()
  assert_eq(@native.ffi_execute_reduce_min_i64(samples, n, 2, 3), -7L)
  assert_eq(@native.ffi_execute_reduce_max_i64(samples, n, 2, 3), 40L)
}
```

### Write into your own output array

Map and scan write into an array you provide and return a status code, `0` on
success:

```moonbit
test "output array" {
  let input : FixedArray[Int64] = [1L, 2L, 3L, 4L]
  let output : FixedArray[Int64] = FixedArray::make(4, 0L)
  let status = @native.ffi_execute_map_i64(input, 4, 2, 2, output)
  assert_eq(status, 0)
  debug_inspect(output, content="<FixedArray: [2, 4, 6, 8]>")
}
```

### Turn a plan into a request

The `*_from_plan` functions check a plan and translate it to the backend's
typed request:

```moonbit
test "request from plan" {
  let policy = @shared.make_execution_policy(worker_count=2, chunk_size=4).unwrap()
  let plan = @plan.scan("prefix", @plan.i64_type(), 8, policy~)
  guard @native.scan_request_from_plan(plan) is Ok(request) else {
    fail("expected a request")
  }
  assert_true(@native.scan_request_is_valid(request))
  assert_eq(request.element_count, 8)
  assert_eq(@native.scan_request_value_type(request), 1)
}
```

### Run a workflow

`submit_workflow_async` starts the graph on worker threads; `wait_workflow`
blocks until it finishes. Because of the known bridge defect described in the
[backend/native API](../../api/backend/native.md), this example is not compiled
into the documentation tests:

```moonbit nocheck
let policy = @shared.make_execution_policy(worker_count=2).unwrap()
let graph = @workflow.Workflow::new("fork-join", policy~)
  .add_node(@workflow.spawn_node(1, "spawn"))
  .add_node(@workflow.join_node(2, "join"))
  .add_edge(@workflow.Edge::new(1, 2, @workflow.control_dependency()))
guard @native.submit_workflow_async(graph) is Ok(handle) else { return }
let result = @native.wait_workflow(handle)
@native.drop_workflow(handle)
// result.state is Completed, result.completed_nodes is 2
```

## Going further

The kernels take the same three numbers $n$, $w$ and $c$, and the
[native backend design](../../design/backend/native.md) derives how they split
the input, why the results do not depend on $w$ and $c$ when they succeed, and
when overflow is detected. To link the C runtime with OpenMP outside MoonBit,
build `native/` with CMake as described in the
[architecture guide](../../architecture.md).

## Common pitfalls

- Every kernel needs $w \ge \lceil n / c \rceil$, $w \le n$ and $c \le n$;
  otherwise it fails with `InvalidArgument` (or returns `0` for reductions).
- The raw functions trust the `length` you pass. Passing more than the array
  holds reads past its end.
- The `moon` build does not enable OpenMP: the kernels run on the calling
  thread even though `supports_openmp()` returns `true`.
- Requests built from plans have empty buffers; nothing executes them yet.
- A workflow whose nodes block without being woken never finishes, and
  `wait_workflow` does not return.

## Next steps

The [backend/native API](../../api/backend/native.md) lists every function,
including the raw ones. The [backend/native design](../../design/backend/native.md)
describes the threading and memory model. The [core tutorial](../core.md)
shows the same kernels through the facade.
