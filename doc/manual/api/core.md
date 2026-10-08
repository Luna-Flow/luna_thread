# core API

## Purpose

The root package `Luna-Flow/luna_thread` is the facade of the module. It
re-exports the common constructors of `plan`, `shared` and `workflow` with
defaults filled in, executes integer kernels on the native backend, and submits
workflows. It builds only for the `native` target. Every function here is a
thin wrapper; the linked package pages give the full semantics of the types it
returns, and the [core design](../design/core.md) explains the defaults.

## Importing

Add the module and import the facade in the `moon.pkg` of a package that builds
for the native target:

```moonbit nocheck
import {
  "Luna-Flow/luna_thread",
  "Luna-Flow/luna_thread/workflow",
}

supported_targets = "native"
```

The examples on this page call the facade as `@luna_thread`. The `workflow`
import is needed only for `@workflow.Edge`, which the facade does not
re-export.

## Module information

### `scaffold_status`

Returns the fixed description `"luna_thread MoonBit facade"`.

```mbti
pub fn scaffold_status() -> String
```

### `root_plan_package` and `root_workflow_package`

Return the names that the `plan` and `workflow` packages report for
themselves, `"plan"` and `"workflow"`.

```mbti
pub fn root_plan_package() -> String
pub fn root_workflow_package() -> String
```

```moonbit
test "module information" {
  inspect(@luna_thread.scaffold_status(), content="luna_thread MoonBit facade")
  inspect(@luna_thread.root_plan_package(), content="plan")
  inspect(@luna_thread.root_workflow_package(), content="workflow")
}
```

## Policies and capabilities

### `default_backend`

Returns `Native`, the backend that plans, workflows and submissions use when
none is given.

```mbti
pub fn default_backend() -> @shared.BackendTarget
```

### `default_policy`

Returns the default execution policy: native backend, synchronous mode, one
worker, chunk size one, input order preserved. It is the same value as
`@shared.native_policy()`.

```mbti
pub fn default_policy() -> @shared.ExecutionPolicy
```

### `javascript_policy`

Builds a policy for the JavaScript backend. It is kept for the JavaScript
backend that the specification describes.

> [!WARNING]
> In v1 the policy constructor rejects every backend other than `Native`, so
> `javascript_policy()` aborts on every call. Use `make_policy` and handle the
> `Err` instead.

```mbti
pub fn javascript_policy() -> @shared.ExecutionPolicy
```

### `make_policy`

Builds an execution policy and checks it, returning the first problem as a
`PolicyError`.

```mbti
pub fn make_policy(backend? : @shared.BackendTarget, mode? : @shared.ExecutionMode, worker_count? : Int, chunk_size? : Int, ordering? : @shared.OrderingGuarantee) -> Result[@shared.ExecutionPolicy, @shared.PolicyError]
```

The defaults are `Native`, `Synchronous`, `1`, `1` and `PreserveInputOrder`.
The checks run in this order and the first failure is returned:
`worker_count > 0`, `chunk_size > 0`, `backend == Native`,
`mode == Synchronous`. The result is the same as
`@shared.make_execution_policy`.

```moonbit
test "make_policy" {
  let policy = @luna_thread.make_policy(worker_count=4, chunk_size=2).unwrap()
  assert_eq(policy.worker_count, 4)
  guard @luna_thread.make_policy(worker_count=0) is Err(error) else {
    fail("expected an error")
  }
  debug_inspect(error.issue, content="WorkerCountMustBePositive(0)")
}
```

### `runtime_capabilities`

Returns the declared capability table of a backend; see
`RuntimeCapabilities::for_backend` in the [shared API](shared.md).

```mbti
pub fn runtime_capabilities(@shared.BackendTarget) -> @shared.RuntimeCapabilities
```

```moonbit
test "runtime_capabilities" {
  let native = @luna_thread.runtime_capabilities(@luna_thread.default_backend())
  assert_true(native.supports_parallelism)
  assert_true(!native.supports_async)
}
```

## Value types and reduction kernels

### `i32_type`, `i64_type`, `f32_type`, `f64_type`, `bytes_type` and `opaque_type`

Return the element types `I32`, `I64`, `F32`, `F64`, `Bytes` and
`Opaque(name)` of a plan's input domain. Only `I32` and `I64` pass validation
in v1.

```mbti
pub fn i32_type() -> @plan.ValueType
pub fn i64_type() -> @plan.ValueType
pub fn f32_type() -> @plan.ValueType
pub fn f64_type() -> @plan.ValueType
pub fn bytes_type() -> @plan.ValueType
pub fn opaque_type(String) -> @plan.ValueType
```

### `sum_reduction`, `min_reduction` and `max_reduction`

Return the reduction kernels `Sum`, `Min` and `Max`, the three kernels that
pass validation in v1.

```mbti
pub fn sum_reduction() -> @plan.ReductionKernel
pub fn min_reduction() -> @plan.ReductionKernel
pub fn max_reduction() -> @plan.ReductionKernel
```

```moonbit
test "value types and kernels" {
  debug_inspect(@luna_thread.i64_type(), content="I64")
  debug_inspect(@luna_thread.opaque_type("rgba"), content="Opaque(\"rgba\")")
  debug_inspect(@luna_thread.max_reduction(), content="Max")
}
```

## Plans

### `map`

Builds a map plan over `input_length` elements of one type.

```mbti
pub fn map(String, @plan.ValueType, Int, policy? : @shared.ExecutionPolicy, ordering? : @shared.OrderingGuarantee) -> @plan.Plan
```

The arguments are the label, the element type and the input length. The
policy defaults to `default_policy()` and the ordering to
`PreserveInputOrder`. The plan is not checked; call `validate` or `is_ready`.

### `reduce`

Builds a reduce plan that combines the input with a reduction kernel.

```mbti
pub fn reduce(String, @plan.ValueType, Int, @plan.ReductionKernel, policy? : @shared.ExecutionPolicy) -> @plan.Plan
```

The ordering of a reduce plan is always `PreserveInputOrder`.

### `scan`

Builds a scan (prefix) plan.

```mbti
pub fn scan(String, @plan.ValueType, Int, policy? : @shared.ExecutionPolicy) -> @plan.Plan
```

A scan has no reduction kernel in the plan and always preserves input order.

### `map_reduce`

Builds a plan that maps every element and then reduces the results.

```mbti
pub fn map_reduce(String, @plan.ValueType, Int, @plan.ReductionKernel, policy? : @shared.ExecutionPolicy, ordering? : @shared.OrderingGuarantee) -> @plan.Plan
```

### `validate`

Returns every reason why a plan is outside the v1 subset, or an empty array.

```mbti
pub fn validate(@plan.Plan) -> Array[@plan.ValidationIssue]
```

This is `@plan.validate`; the [plan API](plan.md) lists the checks.

### `is_ready`

Returns `true` when `validate` finds no issue.

```mbti
pub fn is_ready(@plan.Plan) -> Bool
```

A ready plan satisfies the v1 rules, but the native kernels have one more
requirement, the cover condition $w \ge \lceil n / c \rceil$ described under
`execute_map_i32`.

```moonbit
test "plans" {
  let policy = @luna_thread.make_policy(worker_count=2, chunk_size=4).unwrap()
  let sum = @luna_thread.map_reduce(
    "sum-of-doubles",
    @luna_thread.i32_type(),
    8,
    @luna_thread.sum_reduction(),
    policy~,
  )
  assert_true(@luna_thread.is_ready(sum))
  let floats = @luna_thread.map("halve", @luna_thread.f64_type(), 8, policy~)
  debug_inspect(@luna_thread.validate(floats), content="[UnsupportedValueType]")
}
```

## Direct execution

These functions run a kernel of the native C runtime on a `FixedArray[Int]`
and block until it finishes. They do not use plans. Let $n$ be the input
length, $w$ the worker count and $c$ the chunk size. Every kernel requires

$$
n > 0, \qquad 0 < w \le n, \qquad 0 < c \le n, \qquad w \ge \left\lceil \frac{n}{c} \right\rceil ,
$$

and otherwise fails with `InvalidArgument`. With the defaults $w = c = 1$ only
an input of length one is accepted, so pass both arguments. The input is split
into $\lceil n / c \rceil$ contiguous chunks whose sizes differ by at most one;
the [native backend design](../design/backend/native.md) derives this and the
results below.

### `execute_map_i32`

Doubles every element, returning a new array, or `Overflow` when some
$2 x_i$ does not fit in 32 bits.

```mbti
pub fn execute_map_i32(FixedArray[Int], worker_count? : Int, chunk_size? : Int) -> Result[FixedArray[Int], @native.NativeRequestError]
```

The input is not modified. The map is fixed to $x \mapsto 2x$ in v1.

### `execute_reduce_sum_i32`

Returns the sum of the elements.

```mbti
pub fn execute_reduce_sum_i32(FixedArray[Int], worker_count? : Int, chunk_size? : Int) -> Int
```

The sum is exact when it is returned.

> [!WARNING]
> On any failure, an invalid argument or an overflow of a partial sum, the
> function returns `0`, which cannot be told apart from a true sum of zero.
> With the defaults $w = c = 1$ every input longer than one element fails.
> Whether a partial sum overflows also depends on the chunking:
> `[-1, 0, 2147483647, 1]` sums to `2147483647` with $w = 1, c = 4$ but
> returns `0` with $w = 2, c = 2$.

```moonbit
test "reduce failures look like zero" {
  let input : FixedArray[Int] = [4, 5, 6]
  assert_eq(@luna_thread.execute_reduce_sum_i32(input), 0)
  assert_eq(@luna_thread.execute_reduce_sum_i32(input, worker_count=3, chunk_size=1), 15)
  let edge : FixedArray[Int] = [-1, 0, 2147483647, 1]
  assert_eq(@luna_thread.execute_reduce_sum_i32(edge, worker_count=1, chunk_size=4), 2147483647)
  assert_eq(@luna_thread.execute_reduce_sum_i32(edge, worker_count=2, chunk_size=2), 0)
}
```

### `execute_scan_sum_i32`

Returns the inclusive prefix sums $y_i = x_0 + \dots + x_i$.

```mbti
pub fn execute_scan_sum_i32(FixedArray[Int], worker_count? : Int, chunk_size? : Int) -> Result[FixedArray[Int], @native.NativeRequestError]
```

It fails with `InvalidArgument` when the arguments break the conditions above
and with `Overflow` when a partial sum overflows.

```moonbit
test "direct execution" {
  let input : FixedArray[Int] = [1, 2, 3, 4, 5]
  let doubled = @luna_thread.execute_map_i32(input, worker_count=2, chunk_size=3)
  debug_inspect(doubled, content="Ok(<FixedArray: [2, 4, 6, 8, 10]>)")
  let total = @luna_thread.execute_reduce_sum_i32(
    input,
    worker_count=2,
    chunk_size=3,
  )
  assert_eq(total, 15)
  let prefix = @luna_thread.execute_scan_sum_i32(input, worker_count=2, chunk_size=3)
  debug_inspect(prefix, content="Ok(<FixedArray: [1, 3, 6, 10, 15]>)")
  let rejected = @luna_thread.execute_map_i32(input)
  debug_inspect(rejected, content="Err(InvalidArgument)")
}
```

## Workflows

### `workflow`

Creates an empty workflow with a label and a policy (default
`default_policy()`).

```mbti
pub fn workflow(String, policy? : @shared.ExecutionPolicy) -> @workflow.Workflow
```

Add capabilities, nodes and edges with `Workflow::add_capability`,
`Workflow::add_node` and `Workflow::add_edge` from the
[workflow API](workflow.md). These methods change the workflow in place.

### `compute_task`, `spawn_task` and `join_task`

Create a compute node that carries a plan, a spawn node and a join node.

```mbti
pub fn compute_task(Int, String, @plan.Plan) -> @workflow.Node
pub fn spawn_task(Int, String) -> @workflow.Node
pub fn join_task(Int, String) -> @workflow.Node
```

The first two arguments are the node id and label. None of these nodes needs a
capability.

### `channel_capability`, `mutex_capability` and `shared_read_capability`

Create capabilities with the only access mode that is valid for their kind:
a channel with `MoveOnly`, a mutex with `SynchronizeOnly` and a shared read
view with `ReadOnly`.

```mbti
pub fn channel_capability(Int, String) -> @workflow.Capability
pub fn mutex_capability(Int, String) -> @workflow.Capability
pub fn shared_read_capability(Int, String) -> @workflow.Capability
```

### `workflow_validate` and `workflow_is_ready`

Return the issues found by `@workflow.validate`, and whether there are none.

```mbti
pub fn workflow_validate(@workflow.Workflow) -> Array[@workflow.WorkflowIssue]
pub fn workflow_is_ready(@workflow.Workflow) -> Bool
```

### `submit_workflow`

Validates a workflow for a backend and records the outcome as a `Submission`.

```mbti
pub fn submit_workflow(@workflow.Workflow, backend? : @shared.BackendTarget) -> @workflow.Submission
```

The submission is accepted when the workflow has no issues and the backend is
`Native`. Nothing is executed: `completed` is always `false`. Use
`submit_workflow_async` to run a workflow.

```moonbit
test "workflows" {
  let policy = @luna_thread.make_policy(worker_count=2, chunk_size=2).unwrap()
  let step = @luna_thread.map("double", @luna_thread.i32_type(), 4, policy~)
  let graph = @luna_thread.workflow("pipeline", policy~)
    .add_capability(@luna_thread.channel_capability(1, "jobs"))
    .add_node(@luna_thread.spawn_task(1, "spawn"))
    .add_node(@luna_thread.compute_task(2, "double", step))
    .add_node(@luna_thread.join_task(3, "join"))
    .add_edge(@workflow.Edge::new(1, 2, @workflow.control_dependency()))
    .add_edge(@workflow.Edge::new(2, 3, @workflow.control_dependency()))
  assert_true(@luna_thread.workflow_is_ready(graph))
  let submission = @luna_thread.submit_workflow(graph)
  assert_true(submission.accepted())
  assert_true(!submission.completed())
}
```

## Asynchronous workflows

### `submit_workflow_async`

Starts a workflow on the native runtime and returns a handle at once.

```mbti
pub fn submit_workflow_async(@workflow.Workflow) -> Result[@native.WorkflowHandle, @native.NativeRequestError]
```

The workflow is not validated in MoonBit first; the C runtime checks it. Call
`workflow_validate` yourself before submitting.

> [!WARNING]
> `submit_workflow_async` always returns `Ok`, even when the C runtime rejects
> the graph. A rejected graph gives an empty handle: `wait_workflow` returns at
> once with state `Submitted` and status `7` (`NullPointer`), and the real
> reason is lost.

> [!WARNING]
> The C bridge frees the node, edge and capability arrays, and the request that
> points to them, as soon as the runtime has started, while the worker threads
> still read them. Tests that run workflows crash intermittently because of
> this. Treat asynchronous workflows as experimental until it is fixed.

### `poll_workflow`

Returns a snapshot of a running workflow without waiting.

```mbti
pub fn poll_workflow(@native.WorkflowHandle) -> @native.WorkflowResult
```

### `wait_workflow`

Blocks until the workflow completes or fails, then returns its result.

```mbti
pub fn wait_workflow(@native.WorkflowHandle) -> @native.WorkflowResult
```

`status` is `0` on success or a runtime status code such as `14`
(`BARRIER_BROKEN`); `completed_nodes` counts finished nodes and
`failed_node_id` names the failing node, or is `-1`. A workflow whose nodes
block without being woken never finishes, and `wait_workflow` does not return;
see the [native backend design](../design/backend/native.md).

### `drop_workflow`

Stops the worker threads of a workflow and frees its runtime.

```mbti
pub fn drop_workflow(@native.WorkflowHandle) -> Unit
```

Call it exactly once per handle, after the last `poll_workflow` or
`wait_workflow`.

```moonbit nocheck
let policy = @luna_thread.make_policy(worker_count=2, chunk_size=1).unwrap()
let graph = @luna_thread.workflow("fork-join", policy~)
  .add_node(@luna_thread.spawn_task(1, "spawn"))
  .add_node(@luna_thread.join_task(2, "join"))
  .add_edge(@workflow.Edge::new(1, 2, @workflow.control_dependency()))
guard @luna_thread.submit_workflow_async(graph) is Ok(handle) else { return }
let result = @luna_thread.wait_workflow(handle)
@luna_thread.drop_workflow(handle)
// result: { state: Completed, status: 0, completed_nodes: 2, failed_node_id: -1 }
```

The last example is not compiled into the documentation tests because of the
defect described under `submit_workflow_async`.
