# workflow tutorial

This tutorial gets you describing concurrent work as a task graph: you declare
capabilities, add nodes that use them, order the nodes with edges, and let
`validate` check the result before anything runs. The package works on every
target.

| I want to | Use |
| --- | --- |
| start an empty graph | `@workflow.Workflow::new(label, policy?)` |
| declare a channel, mutex, barrier or shared value | `@workflow.Capability::new(id, label, kind, access)` |
| add a step | `@workflow.spawn_node`, `send_node`, `lock_node`, ... or `compute_node` with a plan |
| say that one step runs after another | `@workflow.Edge::new(from, to, kind)` |
| check the graph | `@workflow.validate(graph)` or `@workflow.is_ready(graph)` |
| run it on threads | `@native.submit_workflow_async(graph)` on the native target |

## Quick start

Add the module, then import the package, and `shared` and `plan` when you need
policies and compute nodes:

```bash
moon add Luna-Flow/luna_thread@0.1.0
```

```moonbit nocheck
import {
  "Luna-Flow/luna_thread/plan",
  "Luna-Flow/luna_thread/shared",
  "Luna-Flow/luna_thread/workflow",
}
```

A fork-join graph with two nodes:

```moonbit
test "workflow quick start" {
  let graph = @workflow.Workflow::new("fork-join")
    .add_node(@workflow.spawn_node(1, "spawn"))
    .add_node(@workflow.join_node(2, "join"))
    .add_edge(@workflow.Edge::new(1, 2, @workflow.control_dependency()))
  inspect(@workflow.is_ready(graph), content="true")
}
```

## Everyday tasks

### Pass work through a channel

Nodes that communicate name a capability by id. A channel is used with
`MoveOnly` access, and the edge from `send` to `recv` makes the receive wait
for the send:

```moonbit
test "channel" {
  let jobs = @workflow.Capability::new(
    1,
    "jobs",
    @workflow.channel_capability(),
    @workflow.move_only_access(),
  )
  let graph = @workflow.Workflow::new("producer-consumer")
    .add_capability(jobs)
    .add_node(@workflow.send_node(1, "produce", capability=1))
    .add_node(@workflow.recv_node(2, "consume", capability=1))
    .add_edge(@workflow.Edge::new(1, 2, @workflow.data_dependency()))
  assert_eq(@workflow.validate(graph).length(), 0)
}
```

### Protect a critical section

A mutex is used with `SynchronizeOnly` access by a `Lock` and an `Unlock`
node:

```moonbit
test "critical section" {
  let guard_cap = @workflow.Capability::new(
    1,
    "guard",
    @workflow.mutex_capability(),
    @workflow.synchronize_only_access(),
  )
  let graph = @workflow.Workflow::new("critical")
    .add_capability(guard_cap)
    .add_node(@workflow.lock_node(1, "enter", capability=1))
    .add_node(@workflow.write_shared_node(2, "update", capability=2))
    .add_node(@workflow.unlock_node(3, "leave", capability=1))
    .add_edge(@workflow.Edge::new(1, 2, @workflow.synchronization_dependency()))
    .add_edge(@workflow.Edge::new(2, 3, @workflow.synchronization_dependency()))
  debug_inspect(@workflow.validate(graph), content="[MissingCapability(capability_id=2)]")
}
```

The write names capability `2`, which the graph does not declare. Adding an
`AtomicCell` with `ReadWrite` access as capability `2` fixes it.

### Embed a plan

A compute node carries a plan, and the plan's own issues are reported with the
node id:

```moonbit
test "compute node" {
  let plan = @plan.map("halve", @plan.f64_type(), 8)
  let graph = @workflow.Workflow::new("compute").add_node(
    @workflow.compute_node(1, "halve", plan),
  )
  debug_inspect(
    @workflow.validate(graph),
    content="[InvalidComputePlan(node_id=1, issue=UnsupportedValueType)]",
  )
  assert_true(@workflow.validate(graph).any(@workflow.is_invalid_compute_plan))
}
```

### Submit a workflow

`submit` validates and records whether the chosen backend accepts the graph:

```moonbit
test "submit" {
  let graph = @workflow.Workflow::new("one").add_node(
    @workflow.spawn_node(1, "spawn"),
  )
  let submission = @workflow.submit(graph)
  inspect(submission.accepted(), content="true")
  inspect(submission.completed(), content="false")
}
```

## Going further

To run a graph, pass it to `@native.submit_workflow_async` (or the facade's
`submit_workflow_async`) on the native target; the
[native backend tutorial](backend/native.md) shows how, and the
[native backend design](../design/backend/native.md) explains which node kinds
can block and what wakes them. Because `validate` returns every issue, a tool
can show all problems of a graph at once; the predicates `is_missing_capability`,
`is_cyclic_dependency`, `is_invalid_compute_plan` and
`is_unsupported_shared_write` group the common ones.

## Common pitfalls

- `add_capability`, `add_node` and `add_edge` change the workflow in place.
  Two variables bound to the same workflow see the same nodes.
- `validate` misses cycles of three or more nodes when some node has no
  incoming edge; the native runtime rejects them on submission.
- A `Recv`, `Lock` or `Send` that can run before its partner may block forever
  on the native runtime. Order such nodes with edges.
- A `Signal` wakes only a `Wait` that is already blocked. Do not join them by
  an edge: `Wait -> Signal` deadlocks, because the `Wait` completes only after
  the `Signal` ran, and `Signal -> Wait` loses the signal. Make the `Wait`
  ready first instead, for example by putting another node in front of the
  `Signal`.
- A single `Barrier` node in a group fails at run time with status `14`; a
  barrier needs at least two nodes at the same depth. Use one barrier
  capability per group: two groups at different depths that share a capability
  share its arrival counter, and the native runtime can then hang.
- `RwLock` and `Semaphore` pass `validate` but are rejected by the native
  runtime.

## Next steps

The [workflow API](../api/workflow.md) lists every check of `validate`. The
[workflow design](../design/workflow.md) gives the graph model and the cycle
checks. The [core tutorial](core.md) builds workflows through the facade.
