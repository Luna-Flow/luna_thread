///|
/// Unified workflow/task-graph package for general concurrency planning.
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
} derive(Eq, Debug)

///|
pub enum AccessMode {
  ReadOnly
  WriteOnly
  ReadWrite
  SynchronizeOnly
  MoveOnly
} derive(Eq, Debug)

///|
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
} derive(Eq, Debug)

///|
pub enum EdgeKind {
  DataDependency
  ControlDependency
  OwnershipTransfer
  SynchronizationDependency
} derive(Eq, Debug)

///|
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
} derive(Eq, Debug)

///|
pub struct Capability {
  id : Int
  label : String
  kind : CapabilityKind
  access : AccessMode
} derive(Eq, Debug)

///|
pub struct Node {
  id : Int
  label : String
  kind : NodeKind
  capability : Int?
} derive(Eq, Debug)

///|
pub struct Edge {
  from : Int
  to : Int
  kind : EdgeKind
} derive(Eq, Debug)

///|
pub struct Workflow {
  label : String
  policy : @shared.ExecutionPolicy
  capabilities : Array[Capability]
  nodes : Array[Node]
  edges : Array[Edge]
} derive(Eq, Debug)

///|
pub struct Submission {
  workflow : Workflow
  backend : @shared.BackendTarget
  accepted : Bool
  completed : Bool
  issues : Array[WorkflowIssue]
} derive(Eq, Debug)

///|
pub fn package_name() -> String {
  "workflow"
}

///|
pub fn owned_buffer_capability() -> CapabilityKind {
  OwnedBuffer
}

///|
pub fn shared_read_view_capability() -> CapabilityKind {
  SharedReadView
}

///|
pub fn atomic_cell_capability() -> CapabilityKind {
  AtomicCell
}

///|
pub fn mutex_capability() -> CapabilityKind {
  Mutex
}

///|
pub fn condvar_capability() -> CapabilityKind {
  Condvar
}

///|
pub fn rwlock_capability() -> CapabilityKind {
  RwLock
}

///|
pub fn semaphore_capability() -> CapabilityKind {
  Semaphore
}

///|
pub fn barrier_capability() -> CapabilityKind {
  Barrier
}

///|
pub fn channel_capability() -> CapabilityKind {
  Channel
}

///|
pub fn opaque_capability(name : String) -> CapabilityKind {
  Opaque(name)
}

///|
pub fn read_only_access() -> AccessMode {
  ReadOnly
}

///|
pub fn write_only_access() -> AccessMode {
  WriteOnly
}

///|
pub fn read_write_access() -> AccessMode {
  ReadWrite
}

///|
pub fn synchronize_only_access() -> AccessMode {
  SynchronizeOnly
}

///|
pub fn move_only_access() -> AccessMode {
  MoveOnly
}

///|
pub fn data_dependency() -> EdgeKind {
  DataDependency
}

///|
pub fn control_dependency() -> EdgeKind {
  ControlDependency
}

///|
pub fn ownership_transfer_dependency() -> EdgeKind {
  OwnershipTransfer
}

///|
pub fn synchronization_dependency() -> EdgeKind {
  SynchronizationDependency
}

///|
pub fn Capability::new(
  id : Int,
  label : String,
  kind : CapabilityKind,
  access : AccessMode,
) -> Capability {
  { id, label, kind, access }
}

///|
pub fn Node::new(
  id : Int,
  label : String,
  kind : NodeKind,
  capability? : Int,
) -> Node {
  { id, label, kind, capability }
}

///|
pub fn Edge::new(from : Int, to : Int, kind : EdgeKind) -> Edge {
  { from, to, kind }
}

///|
pub fn Workflow::new(
  label : String,
  policy? : @shared.ExecutionPolicy = @shared.native_policy(),
) -> Workflow {
  { label, policy, capabilities: [], nodes: [], edges: [] }
}

///|
pub fn compute_node(
  id : Int,
  label : String,
  plan : @plan.Plan,
) -> Node {
  Node::new(id, label, Compute(plan))
}

///|
pub fn spawn_node(id : Int, label : String, capability? : Int) -> Node {
  { id, label, kind: Spawn, capability }
}

///|
pub fn join_node(id : Int, label : String, capability? : Int) -> Node {
  { id, label, kind: Join, capability }
}

///|
pub fn send_node(id : Int, label : String, capability? : Int) -> Node {
  { id, label, kind: Send, capability }
}

///|
pub fn recv_node(id : Int, label : String, capability? : Int) -> Node {
  { id, label, kind: Recv, capability }
}

///|
pub fn lock_node(id : Int, label : String, capability? : Int) -> Node {
  { id, label, kind: Lock, capability }
}

///|
pub fn unlock_node(id : Int, label : String, capability? : Int) -> Node {
  { id, label, kind: Unlock, capability }
}

///|
pub fn wait_node(id : Int, label : String, capability? : Int) -> Node {
  { id, label, kind: Wait, capability }
}

///|
pub fn signal_node(id : Int, label : String, capability? : Int) -> Node {
  { id, label, kind: Signal, capability }
}

///|
pub fn barrier_node(id : Int, label : String, capability? : Int) -> Node {
  { id, label, kind: Barrier, capability }
}

///|
pub fn read_shared_node(id : Int, label : String, capability? : Int) -> Node {
  { id, label, kind: ReadShared, capability }
}

///|
pub fn write_shared_node(id : Int, label : String, capability? : Int) -> Node {
  { id, label, kind: WriteShared, capability }
}

///|
pub fn Workflow::add_capability(
  self : Workflow,
  capability : Capability,
) -> Workflow {
  self.capabilities.push(capability)
  self
}

///|
pub fn Workflow::add_node(
  self : Workflow,
  node : Node,
) -> Workflow {
  self.nodes.push(node)
  self
}

///|
pub fn Workflow::add_edge(
  self : Workflow,
  edge : Edge,
) -> Workflow {
  self.edges.push(edge)
  self
}

///|
fn workflow_has_node_id(workflow : Workflow, node_id : Int) -> Bool {
  workflow.nodes.any(fn(node) { node.id == node_id })
}

///|
fn workflow_has_capability_id(workflow : Workflow, capability_id : Int) -> Bool {
  workflow.capabilities.any(fn(cap) { cap.id == capability_id })
}

///|
fn capability_kind_supported_in_v1(kind : CapabilityKind) -> Bool {
  match kind {
    OwnedBuffer => true
    SharedReadView => true
    AtomicCell => true
    Mutex => true
    Condvar => true
    RwLock => true
    Semaphore => true
    Barrier => true
    Channel => true
    Opaque(_) => false
  }
}

///|
fn capability_access_is_valid(
  kind : CapabilityKind,
  access : AccessMode,
) -> Bool {
  match kind {
    OwnedBuffer => access == ReadOnly || access == WriteOnly || access == ReadWrite
    SharedReadView => access == ReadOnly
    AtomicCell => access == ReadWrite
    Mutex => access == SynchronizeOnly
    Condvar => access == SynchronizeOnly
    RwLock => access == SynchronizeOnly
    Semaphore => access == SynchronizeOnly
    Barrier => access == SynchronizeOnly
    Channel => access == MoveOnly
    Opaque(_) => false
  }
}

///|
fn node_requires_capability(kind : NodeKind) -> Bool {
  match kind {
    Compute(_) => false
    Spawn => false
    Join => false
    Send => true
    Recv => true
    Lock => true
    Unlock => true
    Wait => true
    Signal => true
    Barrier => true
    ReadShared => true
    WriteShared => true
  }
}

///|
fn capability_kind_by_id(
  workflow : Workflow,
  capability_id : Int,
) -> CapabilityKind? {
  for capability in workflow.capabilities {
    if capability.id == capability_id {
      return Some(capability.kind)
    }
  }
  None
}

///|
fn node_matches_capability(
  kind : NodeKind,
  capability_kind : CapabilityKind,
) -> Bool {
  match kind {
    Send => capability_kind == Channel
    Recv => capability_kind == Channel
    Lock => capability_kind == Mutex || capability_kind == RwLock
    Unlock => capability_kind == Mutex || capability_kind == RwLock
    Wait => capability_kind == Condvar
    Signal => capability_kind == Condvar
    Barrier => capability_kind == Barrier
    ReadShared => capability_kind == SharedReadView || capability_kind == AtomicCell
    WriteShared => capability_kind == AtomicCell || capability_kind == OwnedBuffer
    _ => true
  }
}

///|
fn invalid_node_issue(kind : NodeKind, node_id : Int) -> WorkflowIssue {
  match kind {
    Send | Recv => InvalidChannelNode(node_id=node_id)
    Lock | Unlock => InvalidMutexNode(node_id=node_id)
    Wait | Signal => InvalidCondvarNode(node_id=node_id)
    Barrier => InvalidBarrierNode(node_id=node_id)
    _ => InvalidDependency(from_id=node_id, to_id=node_id)
  }
}

///|
fn indegree_of(workflow : Workflow, node_id : Int) -> Int {
  workflow.edges.filter(fn(edge) { edge.to == node_id }).length()
}

///|
fn has_dependency_cycle(workflow : Workflow) -> Bool {
  let zero_indegree = workflow.nodes.filter(fn(node) {
    indegree_of(workflow, node.id) == 0
  }).length()
  if workflow.nodes.length() > 0 && zero_indegree == 0 {
    return true
  }
  workflow.edges.any(fn(edge) {
    workflow.edges.any(fn(other) {
      edge.from == other.to && edge.to == other.from
    })
  })
}

///|
pub fn validate(workflow : Workflow) -> Array[WorkflowIssue] {
  let issues = []
  let policy_issues = @shared.validate_policy(workflow.policy)
  if workflow.nodes.length() == 0 {
    issues.push(EmptyWorkflow)
  }
  for issue in policy_issues {
    issues.push(InvalidPolicy(issue=issue))
  }
  for capability in workflow.capabilities {
    if !capability_kind_supported_in_v1(capability.kind) {
      issues.push(UnsupportedCapability(kind=capability.kind))
    }
    if !capability_access_is_valid(capability.kind, capability.access) {
      issues.push(InvalidCapabilityAccess(capability_id=capability.id))
    }
    let duplicates = workflow.capabilities.filter(fn(other) { other.id == capability.id }).length()
    if duplicates > 1 {
      issues.push(DuplicateCapabilityId(capability_id=capability.id))
    }
  }
  for node in workflow.nodes {
    let duplicates = workflow.nodes.filter(fn(other) { other.id == node.id }).length()
    if duplicates > 1 {
      issues.push(DuplicateNodeId(node_id=node.id))
    }
    if node_requires_capability(node.kind) && node.capability == None {
      issues.push(MissingNodeCapability(node_id=node.id))
    }
    match node.capability {
      Some(capability_id) =>
        if !workflow_has_capability_id(workflow, capability_id) {
          issues.push(MissingCapability(capability_id=capability_id))
        } else {
          match capability_kind_by_id(workflow, capability_id) {
            Some(kind) =>
              if !node_matches_capability(node.kind, kind) {
                issues.push(invalid_node_issue(node.kind, node.id))
              } else if node.kind == WriteShared &&
                workflow.capabilities.any(fn(cap) {
                  cap.id == capability_id && cap.access == ReadOnly
                }) {
                issues.push(UnsupportedSharedWrite(node_id=node.id))
              }
            None => ()
          }
        }
      None => ()
    }
    match node.kind {
      Compute(plan) =>
        for issue in @plan.validate(plan) {
          issues.push(InvalidComputePlan(node_id=node.id, issue=issue))
        }
      _ => ()
    }
  }
  for edge in workflow.edges {
    if edge.from == edge.to {
      issues.push(SelfEdge(node_id=edge.from))
    }
    if !workflow_has_node_id(workflow, edge.from) {
      issues.push(InvalidNodeReference(node_id=edge.from))
    }
    if !workflow_has_node_id(workflow, edge.to) {
      issues.push(InvalidNodeReference(node_id=edge.to))
    }
    if !workflow_has_node_id(workflow, edge.from) ||
      !workflow_has_node_id(workflow, edge.to) {
      issues.push(InvalidDependency(from_id=edge.from, to_id=edge.to))
    }
  }
  if workflow.nodes.length() > 0 && has_dependency_cycle(workflow) {
    issues.push(CyclicDependency)
  }
  issues
}

///|
pub fn is_ready(workflow : Workflow) -> Bool {
  validate(workflow).length() == 0
}

///|
pub fn submit(
  workflow : Workflow,
  backend? : @shared.BackendTarget = @shared.native_target(),
) -> Submission {
  let issues = validate(workflow)
  let accepted = issues.length() == 0 && backend == @shared.native_target()
  {
    workflow,
    backend,
    accepted,
    completed: false,
    issues,
  }
}

///|
pub fn Submission::accepted(self : Submission) -> Bool {
  self.accepted
}

///|
pub fn Submission::issues(self : Submission) -> Array[WorkflowIssue] {
  self.issues
}

///|
pub fn Submission::completed(self : Submission) -> Bool {
  self.completed
}

///|
pub fn Submission::backend(self : Submission) -> @shared.BackendTarget {
  self.backend
}

///|
pub fn Workflow::label(self : Workflow) -> String {
  self.label
}

///|
pub fn Workflow::policy(self : Workflow) -> @shared.ExecutionPolicy {
  self.policy
}

///|
pub fn Workflow::capabilities(self : Workflow) -> Array[Capability] {
  self.capabilities
}

///|
pub fn Workflow::nodes(self : Workflow) -> Array[Node] {
  self.nodes
}

///|
pub fn Workflow::edges(self : Workflow) -> Array[Edge] {
  self.edges
}

///|
pub fn is_invalid_compute_plan(issue : WorkflowIssue) -> Bool {
  match issue {
    InvalidComputePlan(..) => true
    _ => false
  }
}

///|
pub fn is_cyclic_dependency(issue : WorkflowIssue) -> Bool {
  match issue {
    CyclicDependency => true
    _ => false
  }
}

///|
pub fn is_missing_capability(issue : WorkflowIssue) -> Bool {
  match issue {
    MissingCapability(..) => true
    MissingNodeCapability(..) => true
    _ => false
  }
}

///|
pub fn is_unsupported_shared_write(issue : WorkflowIssue) -> Bool {
  match issue {
    UnsupportedSharedWrite(..) => true
    _ => false
  }
}
