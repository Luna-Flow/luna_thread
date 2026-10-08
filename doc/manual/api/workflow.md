# workflow API

The package `Luna-Flow/luna_thread/workflow`, imported as `@workflow`,
describes a task graph: a set of capabilities (channels, locks, barriers and
shared data), a set of nodes that compute or synchronise, and dependency edges
between nodes. It validates the graph and records submissions. It executes
nothing itself and builds on every target; `backend/native` runs workflows.

The enumerations of this package are read-only outside it: match on their
constructors, but build values with the functions below.

## Capabilities

### `CapabilityKind`

The kind of resource a capability stands for.

```mbti
pub enum CapabilityKind {
  OwnedBuffer
  SharedReadView
  AtomicCell
  Mutex
  Condvar
  RwLock
  Semaphore
  Barrier
  Channel
  Opaque(String)
} derive(Eq, @debug.Debug)
```

`Opaque(name)` is never supported. The native runtime additionally rejects
`RwLock` and `Semaphore`.

### `AccessMode`

How nodes may use a capability.

```mbti
pub enum AccessMode {
  ReadOnly
  WriteOnly
  ReadWrite
  SynchronizeOnly
  MoveOnly
} derive(Eq, @debug.Debug)
```

Each capability kind admits only some access modes:

| Kind | Valid access modes |
| --- | --- |
| `OwnedBuffer` | `ReadOnly`, `WriteOnly`, `ReadWrite` |
| `SharedReadView` | `ReadOnly` |
| `AtomicCell` | `ReadWrite` |
| `Mutex`, `Condvar`, `RwLock`, `Semaphore`, `Barrier` | `SynchronizeOnly` |
| `Channel` | `MoveOnly` |
| `Opaque(_)` | none |

### `Capability`

A capability with an id, a label, a kind and an access mode.

```mbti
pub struct Capability {
  id : Int
  label : String
  kind : CapabilityKind
  access : AccessMode
} derive(Eq, @debug.Debug)
pub fn Capability::new(Int, String, CapabilityKind, AccessMode) -> Self
```

`Capability::new` does not check the access mode; `validate` does.

### `owned_buffer_capability`, `shared_read_view_capability`, `atomic_cell_capability`, `mutex_capability`, `condvar_capability`, `rwlock_capability`, `semaphore_capability`, `barrier_capability`, `channel_capability` and `opaque_capability`

Return the capability kinds of the same names.

```mbti
pub fn owned_buffer_capability() -> CapabilityKind
pub fn shared_read_view_capability() -> CapabilityKind
pub fn atomic_cell_capability() -> CapabilityKind
pub fn mutex_capability() -> CapabilityKind
pub fn condvar_capability() -> CapabilityKind
pub fn rwlock_capability() -> CapabilityKind
pub fn semaphore_capability() -> CapabilityKind
pub fn barrier_capability() -> CapabilityKind
pub fn channel_capability() -> CapabilityKind
pub fn opaque_capability(String) -> CapabilityKind
```

### `read_only_access`, `write_only_access`, `read_write_access`, `synchronize_only_access` and `move_only_access`

Return the access modes of the same names.

```mbti
pub fn read_only_access() -> AccessMode
pub fn write_only_access() -> AccessMode
pub fn read_write_access() -> AccessMode
pub fn synchronize_only_access() -> AccessMode
pub fn move_only_access() -> AccessMode
```

```moonbit
test "capabilities" {
  let lock = @workflow.Capability::new(
    1,
    "guard",
    @workflow.mutex_capability(),
    @workflow.synchronize_only_access(),
  )
  assert_true(lock.kind is @workflow.Mutex)
  assert_true(lock.access is @workflow.SynchronizeOnly)
}
```

## Nodes

### `NodeKind`

What a node does.

```mbti
pub enum NodeKind {
  Compute(@plan.Plan)
  Spawn
  Join
  Send
  Recv
  Lock
  Unlock
  Wait
  Signal
  Barrier
  ReadShared
  WriteShared
} derive(Eq, @debug.Debug)
```

`Compute`, `Spawn` and `Join` need no capability. The other kinds must name a
capability of a matching kind:

| Node kind | Capability kinds |
| --- | --- |
| `Send`, `Recv` | `Channel` |
| `Lock`, `Unlock` | `Mutex`, `RwLock` |
| `Wait`, `Signal` | `Condvar` |
| `Barrier` | `Barrier` |
| `ReadShared` | `SharedReadView`, `AtomicCell` |
| `WriteShared` | `AtomicCell`, `OwnedBuffer` (not with `ReadOnly` access) |

### `Node`

A node with an id, a label, a kind and an optional capability id.

```mbti
pub struct Node {
  id : Int
  label : String
  kind : NodeKind
  capability : Int?
} derive(Eq, @debug.Debug)
pub fn Node::new(Int, String, NodeKind, capability? : Int) -> Self
```

### `compute_node`

Creates a `Compute(plan)` node without a capability.

```mbti
pub fn compute_node(Int, String, @plan.Plan) -> Node
```

### `spawn_node`, `join_node`, `send_node`, `recv_node`, `lock_node`, `unlock_node`, `wait_node`, `signal_node`, `barrier_node`, `read_shared_node` and `write_shared_node`

Create a node of the kind of the same name, with an id, a label and an
optional capability id.

```mbti
pub fn spawn_node(Int, String, capability? : Int) -> Node
pub fn join_node(Int, String, capability? : Int) -> Node
pub fn send_node(Int, String, capability? : Int) -> Node
pub fn recv_node(Int, String, capability? : Int) -> Node
pub fn lock_node(Int, String, capability? : Int) -> Node
pub fn unlock_node(Int, String, capability? : Int) -> Node
pub fn wait_node(Int, String, capability? : Int) -> Node
pub fn signal_node(Int, String, capability? : Int) -> Node
pub fn barrier_node(Int, String, capability? : Int) -> Node
pub fn read_shared_node(Int, String, capability? : Int) -> Node
pub fn write_shared_node(Int, String, capability? : Int) -> Node
```

```moonbit
test "nodes" {
  let send = @workflow.send_node(2, "send", capability=1)
  assert_eq(send.capability, Some(1))
  assert_true(send.kind is @workflow.Send)
  assert_eq(@workflow.join_node(3, "join").capability, None)
}
```

## Edges

### `EdgeKind`

Why one node must run before another.

```mbti
pub enum EdgeKind {
  DataDependency
  ControlDependency
  OwnershipTransfer
  SynchronizationDependency
} derive(Eq, @debug.Debug)
```

All four kinds order their endpoints in the same way; the kind documents the
reason and is passed to the runtime unchanged.

### `Edge`

A dependency from node `from` to node `to`: `to` may start only after `from`
has completed.

```mbti
pub struct Edge {
  from : Int
  to : Int
  kind : EdgeKind
} derive(Eq, @debug.Debug)
pub fn Edge::new(Int, Int, EdgeKind) -> Self
```

### `data_dependency`, `control_dependency`, `ownership_transfer_dependency` and `synchronization_dependency`

Return `DataDependency`, `ControlDependency`, `OwnershipTransfer` and
`SynchronizationDependency`.

```mbti
pub fn data_dependency() -> EdgeKind
pub fn control_dependency() -> EdgeKind
pub fn ownership_transfer_dependency() -> EdgeKind
pub fn synchronization_dependency() -> EdgeKind
```

## Workflows

### `Workflow`

A labelled task graph with an execution policy.

```mbti
pub struct Workflow {
  label : String
  policy : @shared.ExecutionPolicy
  capabilities : Array[Capability]
  nodes : Array[Node]
  edges : Array[Edge]
} derive(Eq, @debug.Debug)
pub fn Workflow::new(String, policy? : @shared.ExecutionPolicy) -> Self
```

`Workflow::new` creates an empty graph; `policy` defaults to
`@shared.native_policy()`.

### `Workflow::add_capability`, `Workflow::add_node` and `Workflow::add_edge`

Append a capability, node or edge and return the same workflow.

```mbti
pub fn Workflow::add_capability(Self, Capability) -> Self
pub fn Workflow::add_node(Self, Node) -> Self
pub fn Workflow::add_edge(Self, Edge) -> Self
```

These methods push onto the workflow's arrays in place: the receiver and the
result are the same value, and every other reference to the workflow sees the
addition. They do not check anything.

### `Workflow::label`, `Workflow::policy`, `Workflow::capabilities`, `Workflow::nodes` and `Workflow::edges`

Return the fields of a workflow. The arrays are the workflow's own arrays, not
copies.

```mbti
pub fn Workflow::label(Self) -> String
pub fn Workflow::policy(Self) -> @shared.ExecutionPolicy
pub fn Workflow::capabilities(Self) -> Array[Capability]
pub fn Workflow::nodes(Self) -> Array[Node]
pub fn Workflow::edges(Self) -> Array[Edge]
```

```moonbit
test "building a workflow" {
  let graph = @workflow.Workflow::new("fork-join")
    .add_node(@workflow.spawn_node(1, "spawn"))
    .add_node(@workflow.join_node(2, "join"))
    .add_edge(@workflow.Edge::new(1, 2, @workflow.control_dependency()))
  assert_eq(graph.nodes().length(), 2)
  assert_eq(graph.label(), "fork-join")
}
```

## Validation

### `WorkflowIssue`

One problem found in a workflow.

```mbti
pub enum WorkflowIssue {
  EmptyWorkflow
  InvalidNodeReference(node_id~ : Int)
  SelfEdge(node_id~ : Int)
  CyclicDependency
  DuplicateNodeId(node_id~ : Int)
  DuplicateCapabilityId(capability_id~ : Int)
  MissingCapability(capability_id~ : Int)
  MissingNodeCapability(node_id~ : Int)
  InvalidDependency(from_id~ : Int, to_id~ : Int)
  UnsupportedSharedWrite(node_id~ : Int)
  InvalidCapabilityAccess(capability_id~ : Int)
  InvalidChannelNode(node_id~ : Int)
  InvalidMutexNode(node_id~ : Int)
  InvalidCondvarNode(node_id~ : Int)
  InvalidBarrierNode(node_id~ : Int)
  UnsupportedCapability(kind~ : CapabilityKind)
  InvalidPolicy(issue~ : @shared.PolicyIssue)
  InvalidComputePlan(node_id~ : Int, issue~ : @plan.ValidationIssue)
} derive(Eq, @debug.Debug)
```

### `validate`

Returns every issue of a workflow, or an empty array.

```mbti
pub fn validate(Workflow) -> Array[WorkflowIssue]
```

The checks, in the order their issues appear:

1. `EmptyWorkflow` when there are no nodes, then one `InvalidPolicy` per issue
   of `@shared.validate_policy` on the workflow's policy.
2. For each capability: `UnsupportedCapability` for `Opaque`,
   `InvalidCapabilityAccess` when the access mode is not valid for the kind,
   and `DuplicateCapabilityId` when its id occurs more than once (reported
   once per occurrence).
3. For each node: `DuplicateNodeId` (once per occurrence),
   `MissingNodeCapability` when the kind needs a capability and has none,
   `MissingCapability` when the named capability does not exist, an
   `InvalidChannelNode`, `InvalidMutexNode`, `InvalidCondvarNode` or
   `InvalidBarrierNode` when the capability has the wrong kind (an
   `InvalidDependency` with equal endpoints for the other node kinds),
   `UnsupportedSharedWrite` when a `WriteShared` node names a `ReadOnly`
   capability, and one `InvalidComputePlan` per issue of `@plan.validate` on a
   compute node's plan.
4. For each edge: `SelfEdge` when `from == to`, `InvalidNodeReference` for each
   endpoint that is not a node, and `InvalidDependency` when either is not.
5. `CyclicDependency` when the graph has no node without incoming edges, or
   when two edges point in opposite directions between the same nodes.

The cycle check in step 5 does not find every cycle: a cycle of three or more
nodes that is reachable from a source passes. The native runtime checks for
cycles completely and rejects such a graph when it is submitted. The
[workflow design](../design/workflow.md) discusses both checks.

### `is_ready`

Returns `true` when `validate` returns no issue.

```mbti
pub fn is_ready(Workflow) -> Bool
```

### `is_invalid_compute_plan`, `is_cyclic_dependency`, `is_missing_capability` and `is_unsupported_shared_write`

Test which issue a `WorkflowIssue` is.

```mbti
pub fn is_invalid_compute_plan(WorkflowIssue) -> Bool
pub fn is_cyclic_dependency(WorkflowIssue) -> Bool
pub fn is_missing_capability(WorkflowIssue) -> Bool
pub fn is_unsupported_shared_write(WorkflowIssue) -> Bool
```

`is_missing_capability` matches both `MissingCapability` and
`MissingNodeCapability`.

```moonbit
test "validation" {
  let graph = @workflow.Workflow::new("bad").add_node(
    @workflow.write_shared_node(1, "write", capability=7),
  )
  let issues = @workflow.validate(graph)
  debug_inspect(issues, content="[MissingCapability(capability_id=7)]")
  assert_true(issues.any(@workflow.is_missing_capability))
  assert_true(!@workflow.is_ready(graph))
}
```

## Submission

### `Submission`

The record of a submission: the workflow, the target backend, whether it was
accepted and completed, and the issues found.

```mbti
pub struct Submission {
  workflow : Workflow
  backend : @shared.BackendTarget
  accepted : Bool
  completed : Bool
  issues : Array[WorkflowIssue]
} derive(Eq, @debug.Debug)
pub fn Submission::accepted(Self) -> Bool
pub fn Submission::backend(Self) -> @shared.BackendTarget
pub fn Submission::completed(Self) -> Bool
pub fn Submission::issues(Self) -> Array[WorkflowIssue]
```

### `submit`

Validates a workflow and records whether the backend accepts it.

```mbti
pub fn submit(Workflow, backend? : @shared.BackendTarget) -> Submission
```

The submission is accepted exactly when `validate` returns no issue and the
backend (default `Native`) is `Native`. `completed` is always `false`: `submit`
does not run the workflow.

```moonbit
test "submit" {
  let graph = @workflow.Workflow::new("one").add_node(
    @workflow.spawn_node(1, "spawn"),
  )
  let native = @workflow.submit(graph)
  assert_true(native.accepted() && !native.completed())
  let js = @workflow.submit(graph, backend=@shared.javascript_target())
  assert_true(!js.accepted())
  assert_eq(js.issues().length(), 0)
}
```

## Equality and package information

### `T::equal`

Structural equality, promoted on every type of the package: `AccessMode`,
`Capability`, `CapabilityKind`, `Edge`, `EdgeKind`, `Node`, `NodeKind`,
`Submission`, `Workflow` and `WorkflowIssue`. Use `==` and `!=`.

```mbti
pub fn Workflow::equal(Self, Self) -> Bool
```

### `package_name`

Returns `"workflow"`.

```mbti
pub fn package_name() -> String
```
