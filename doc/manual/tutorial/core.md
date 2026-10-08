# core tutorial

This tutorial shows you how to run parallel integer kernels from MoonBit with
the `luna_thread` facade, how to describe the same work as a plan that the
library validates, and how to build and check a workflow graph. Everything
runs on the native target.

## Quick start

Add the module:

```text
moon add Luna-Flow/luna_thread@0.1.0
```

Import the facade from a package that builds for the native target:

```text
import {
  "Luna-Flow/luna_thread",
}

supported_targets = "native"
```

Sum an array with two workers that each take a chunk of up to three elements:

```moonbit
test "quick start" {
  let input : FixedArray[Int] = [1, 2, 3, 4, 5, 6]
  let total = @luna_thread.execute_reduce_sum_i32(
    input,
    worker_count=2,
    chunk_size=3,
  )
  inspect(total, content="21")
}
```

`moon test --target native` reports:

```text
Total tests: 1, passed: 1, failed: 0.
```

## Everyday tasks

### Choose the worker count and chunk size

The kernels split $n$ elements into $\lceil n / c \rceil$ chunks of at most $c$
elements and need one worker per chunk, so pick $c$ first and then
$w = \lceil n / c \rceil$. Both must also be at most $n$.

```moonbit
fn chunked_sum(input : FixedArray[Int], chunk_size : Int) -> Int {
  let n = input.length()
  let workers = (n + chunk_size - 1) / chunk_size
  @luna_thread.execute_reduce_sum_i32(input, worker_count=workers, chunk_size~)
}

test "choose the parameters" {
  let input : FixedArray[Int] = [10, 20, 30, 40, 50, 60, 70]
  inspect(chunked_sum(input, 3), content="280")
  inspect(chunked_sum(input, 7), content="280")
}
```

### Double the elements and handle overflow

`execute_map_i32` doubles every element and reports overflow as an error
instead of wrapping around:

```moonbit
test "map with overflow" {
  let small : FixedArray[Int] = [1, -2, 3, 4]
  debug_inspect(
    @luna_thread.execute_map_i32(small, worker_count=2, chunk_size=2),
    content="Ok(<FixedArray: [2, -4, 6, 8]>)",
  )
  let large : FixedArray[Int] = [1, 2147483647]
  debug_inspect(
    @luna_thread.execute_map_i32(large, worker_count=2, chunk_size=1),
    content="Err(Overflow)",
  )
}
```

### Compute prefix sums

`execute_scan_sum_i32` returns the running totals:

```moonbit
test "prefix sums" {
  let deposits : FixedArray[Int] = [100, -30, 50, 20, -10]
  match @luna_thread.execute_scan_sum_i32(deposits, worker_count=2, chunk_size=3) {
    Ok(balance) => debug_inspect(balance, content="<FixedArray: [100, 70, 120, 140, 130]>")
    Err(error) => fail("scan failed: \{Repr(error)}")
  }
}
```

### Describe the work as a plan and validate it

A plan records what should run without running it. Validation tells you
whether the v1 runtime supports it:

```moonbit
test "plans" {
  let policy = @luna_thread.make_policy(worker_count=2, chunk_size=3).unwrap()
  let plan = @luna_thread.reduce(
    "total",
    @luna_thread.i32_type(),
    6,
    @luna_thread.sum_reduction(),
    policy~,
  )
  assert_true(@luna_thread.is_ready(plan))
  let doubles = @luna_thread.map("halve", @luna_thread.f64_type(), 6, policy~)
  debug_inspect(@luna_thread.validate(doubles), content="[UnsupportedValueType]")
}
```

### Build and check a workflow

A workflow is a graph of tasks. This one spawns, computes the plan above and
joins, with edges that fix the order:

```moonbit
test "workflow" {
  let policy = @luna_thread.make_policy(worker_count=2, chunk_size=3).unwrap()
  let plan = @luna_thread.reduce(
    "total",
    @luna_thread.i32_type(),
    6,
    @luna_thread.sum_reduction(),
    policy~,
  )
  let graph = @luna_thread.workflow("sum-job", policy~)
    .add_node(@luna_thread.spawn_task(1, "spawn"))
    .add_node(@luna_thread.compute_task(2, "sum", plan))
    .add_node(@luna_thread.join_task(3, "join"))
    .add_edge(@workflow.Edge::new(1, 2, @workflow.control_dependency()))
    .add_edge(@workflow.Edge::new(2, 3, @workflow.control_dependency()))
  assert_true(@luna_thread.workflow_is_ready(graph))
  let submission = @luna_thread.submit_workflow(graph)
  inspect(submission.accepted(), content="true")
}
```

This needs `"Luna-Flow/luna_thread/workflow"` in the imports as well, for
`Edge`. `submit_workflow` validates and records the submission; it does not run
the graph.

## Going further

To run a workflow's synchronisation protocol on real threads, submit it with
`submit_workflow_async`, then `wait_workflow` and `drop_workflow`. The
asynchronous path is experimental because of a known defect in the C bridge;
read the warning in the [core API](../api/core.md) before you use it.

For other element types and kernels, `backend/native` exposes the raw C
entry points, including `Int64` and minimum and maximum reductions; see the
[native backend tutorial](backend/native.md). For finer control over plans and
graphs, use the `plan` and `workflow` packages directly: the
[plan tutorial](plan.md) and the [workflow tutorial](workflow.md) build
plans and graphs field by field. Packages that only describe work can import
those two packages and build for every target.

## Common pitfalls

- The defaults `worker_count=1` and `chunk_size=1` only work for one-element
  inputs. For longer inputs the kernels return `Err(InvalidArgument)`, and
  `execute_reduce_sum_i32` returns `0`.
- `execute_reduce_sum_i32` returns `0` both for a sum of zero and for any
  failure. Check the input and parameters yourself, or use the scan and take
  the last element when you need to tell them apart.
- Whether an `Int` sum overflows can depend on the chunking, because partial
  sums are checked: `[-1, 0, 2147483647, 1]` sums with `chunk_size=4` and fails
  with `chunk_size=2`.
- `is_ready` does not check the worker-per-chunk condition, so a ready plan
  can still be rejected by a kernel.
- `javascript_policy()` aborts in v1, and `make_policy` rejects the JavaScript
  backend and asynchronous mode.
- `Workflow::add_node` and the other builders change the workflow in place.
- The facade builds only for the native target. Packages that import it need
  `supported_targets = "native"` or a native-only build.

## Next steps

The [core API](../api/core.md) lists every facade function with its exact
semantics. The [core design](../design/core.md) explains why the facade is a
set of free functions with defaults, and the
[native backend design](../design/backend/native.md) explains how the kernels
and the workflow scheduler use threads and memory. The
[architecture guide](../architecture.md) shows how the packages and the C
runtime fit together.
