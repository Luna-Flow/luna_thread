///|
/// Native backend package. Keep C FFI declarations and native wrapper code here.
pub enum NativeValueType {
  I32
  I64
} derive(Eq, Debug)

///|
pub enum NativeReductionKernel {
  Sum
  Min
  Max
} derive(Eq, Debug)

///|
pub enum NativeRequestError {
  UnsupportedBackend
  UnsupportedMode
  UnsupportedValueType
  UnsupportedReductionKernel
  InvalidArgument
  Overflow
} derive(Eq, Debug)

///|
pub enum WorkflowRuntimeState {
  Submitted
  Running
  Completed
  Failed
  Rejected
} derive(Eq, Debug)

///|
pub struct WorkflowHandle {
  raw : NativeWorkflowHandle
}

///|
pub struct WorkflowResult {
  state : WorkflowRuntimeState
  status : Int
  completed_nodes : Int
  failed_node_id : Int
} derive(Eq, Debug)

///|
pub struct NativeMapRequest {
  input : @shared.NativeBuffer
  output : @shared.NativeBuffer
  element_count : Int
  value_type : NativeValueType
  worker_count : Int
  chunk_size : Int
} derive(Eq, Debug)

///|
pub struct NativeReduceRequest {
  input : @shared.NativeBuffer
  output : @shared.NativeBuffer
  element_count : Int
  value_type : NativeValueType
  reduction_kernel : NativeReductionKernel
  worker_count : Int
  chunk_size : Int
} derive(Eq, Debug)

///|
pub struct NativeScanRequest {
  input : @shared.NativeBuffer
  output : @shared.NativeBuffer
  element_count : Int
  value_type : NativeValueType
  reduction_kernel : NativeReductionKernel
  worker_count : Int
  chunk_size : Int
} derive(Eq, Debug)

///|
pub fn backend_target() -> @shared.BackendTarget {
  @shared.native_target()
}

///|
pub fn package_name() -> String {
  "backend/native"
}

///|
pub fn default_plan_kind() -> @plan.PlanKind {
  @plan.map_plan_kind()
}

///|
pub fn supports_openmp() -> Bool {
  true
}

///|
pub fn workflow_is_supported(
  workflow : @workflow.Workflow,
) -> Bool {
  @workflow.validate(workflow).length() == 0 &&
  workflow.policy().backend == @shared.native_target()
}

///|
pub fn submit_workflow(
  workflow : @workflow.Workflow,
) -> @workflow.Submission {
  @workflow.submit(workflow, backend=@shared.native_target())
}

///|
pub fn execute_map_i32(
  input : FixedArray[Int],
  worker_count : Int,
  chunk_size : Int,
) -> Result[FixedArray[Int], NativeRequestError] {
  let output = FixedArray::make(input.length(), 0)
  let status = ffi_execute_map_i32(
    input,
    input.length(),
    worker_count,
    chunk_size,
    output,
  )
  guard status == 0 else { return Err(status_code_to_error(status)) }
  Ok(output)
}

///|
pub fn execute_reduce_sum_i32(
  input : FixedArray[Int],
  worker_count : Int,
  chunk_size : Int,
) -> Int {
  ffi_execute_reduce_sum_i32(input, input.length(), worker_count, chunk_size)
}

///|
pub fn execute_scan_sum_i32(
  input : FixedArray[Int],
  worker_count : Int,
  chunk_size : Int,
) -> Result[FixedArray[Int], NativeRequestError] {
  let output = FixedArray::make(input.length(), 0)
  let status = ffi_execute_scan_sum_i32(
    input,
    input.length(),
    worker_count,
    chunk_size,
    output,
  )
  guard status == 0 else { return Err(status_code_to_error(status)) }
  Ok(output)
}

///|
pub fn submit_workflow_async(
  workflow : @workflow.Workflow,
) -> Result[WorkflowHandle, NativeRequestError] {
  let capabilities = workflow.capabilities()
  let nodes = workflow.nodes()
  let edges = workflow.edges()
  let capability_ids = FixedArray::make(capabilities.length(), 0)
  let capability_kinds = FixedArray::make(capabilities.length(), 0)
  for i = 0; i < capabilities.length(); i = i + 1 {
    capability_ids[i] = capabilities[i].id
    capability_kinds[i] = capability_kind_code(capabilities[i].kind)
  }
  let node_ids = FixedArray::make(nodes.length(), 0)
  let node_kinds = FixedArray::make(nodes.length(), 0)
  let node_caps = FixedArray::make(nodes.length(), -1)
  for i = 0; i < nodes.length(); i = i + 1 {
    node_ids[i] = nodes[i].id
    node_kinds[i] = node_kind_code(nodes[i].kind)
    match nodes[i].capability {
      Some(id) => node_caps[i] = id
      None => ()
    }
  }
  let edge_froms = FixedArray::make(edges.length(), 0)
  let edge_tos = FixedArray::make(edges.length(), 0)
  let edge_kinds = FixedArray::make(edges.length(), 0)
  for i = 0; i < edges.length(); i = i + 1 {
    edge_froms[i] = edges[i].from
    edge_tos[i] = edges[i].to
    edge_kinds[i] = edge_kind_code(edges[i].kind)
  }
  let raw = ffi_submit_workflow_async(
    workflow.policy().worker_count,
    capability_ids,
    capability_kinds,
    capabilities.length(),
    node_ids,
    node_kinds,
    node_caps,
    nodes.length(),
    edge_froms,
    edge_tos,
    edge_kinds,
    edges.length(),
  )
  Ok(WorkflowHandle::{ raw })
}

///|
pub fn poll_workflow(handle : WorkflowHandle) -> WorkflowResult {
  {
    state: workflow_state_from_code(ffi_workflow_poll_state(handle.raw)),
    status: ffi_workflow_poll_status(handle.raw),
    completed_nodes: ffi_workflow_poll_completed_nodes(handle.raw),
    failed_node_id: ffi_workflow_poll_failed_node_id(handle.raw),
  }
}

///|
pub fn wait_workflow(handle : WorkflowHandle) -> WorkflowResult {
  let wait_status = ffi_workflow_wait_status(handle.raw)
  {
    state: workflow_state_from_code(ffi_workflow_poll_state(handle.raw)),
    status: wait_status,
    completed_nodes: ffi_workflow_poll_completed_nodes(handle.raw),
    failed_node_id: ffi_workflow_poll_failed_node_id(handle.raw),
  }
}

///|
pub fn drop_workflow(handle : WorkflowHandle) -> Unit {
  ffi_workflow_destroy(handle.raw)
}

///|
pub fn map_request_from_plan(
  plan : @plan.Plan,
) -> Result[NativeMapRequest, NativeRequestError] {
  guard @plan.is_map(plan) else { return Err(UnsupportedMode) }
  guard @plan.validate(plan).length() == 0 else {
    return Err(request_error_from_issue(@plan.validate(plan)[0]))
  }
  let value_type = match plan.domain().element_type() {
    I32 => NativeValueType::I32
    I64 => NativeValueType::I64
    _ => return Err(UnsupportedValueType)
  }
  Ok(NativeMapRequest::{
    input: @shared.NativeBuffer::new(0, 0),
    output: @shared.NativeBuffer::new(0, 0),
    element_count: plan.domain().input_length(),
    value_type,
    worker_count: plan.policy().worker_count,
    chunk_size: plan.policy().chunk_size,
  })
}

///|
pub fn reduce_request_from_plan(
  plan : @plan.Plan,
) -> Result[NativeReduceRequest, NativeRequestError] {
  guard @plan.is_reduce(plan) || @plan.is_map_reduce(plan) else {
    return Err(UnsupportedMode)
  }
  guard @plan.validate(plan).length() == 0 else {
    return Err(request_error_from_issue(@plan.validate(plan)[0]))
  }
  let value_type = match plan.domain().element_type() {
    I32 => NativeValueType::I32
    I64 => NativeValueType::I64
    _ => return Err(UnsupportedValueType)
  }
  let reduction_kernel = match plan.reduction() {
    Some(sum) =>
      match sum {
        @plan.Sum => NativeReductionKernel::Sum
        @plan.Min => NativeReductionKernel::Min
        @plan.Max => NativeReductionKernel::Max
        _ => return Err(UnsupportedReductionKernel)
      }
    None => return Err(UnsupportedReductionKernel)
  }
  Ok(NativeReduceRequest::{
    input: @shared.NativeBuffer::new(0, 0),
    output: @shared.NativeBuffer::new(0, 0),
    element_count: plan.domain().input_length(),
    value_type,
    reduction_kernel,
    worker_count: plan.policy().worker_count,
    chunk_size: plan.policy().chunk_size,
  })
}

///|
pub fn scan_request_from_plan(
  plan : @plan.Plan,
) -> Result[NativeScanRequest, NativeRequestError] {
  guard @plan.is_scan(plan) else { return Err(UnsupportedMode) }
  guard @plan.validate(plan).length() == 0 else {
    return Err(request_error_from_issue(@plan.validate(plan)[0]))
  }
  let value_type = match plan.domain().element_type() {
    I32 => NativeValueType::I32
    I64 => NativeValueType::I64
    _ => return Err(UnsupportedValueType)
  }
  Ok(NativeScanRequest::{
    input: @shared.NativeBuffer::new(0, 0),
    output: @shared.NativeBuffer::new(0, 0),
    element_count: plan.domain().input_length(),
    value_type,
    reduction_kernel: NativeReductionKernel::Sum,
    worker_count: plan.policy().worker_count,
    chunk_size: plan.policy().chunk_size,
  })
}

///|
pub fn map_request_is_valid(req : NativeMapRequest) -> Bool {
  req.element_count > 0 &&
  req.worker_count > 0 &&
  req.chunk_size > 0 &&
  (
    req.value_type == NativeValueType::I32 ||
    req.value_type == NativeValueType::I64
  )
}

///|
pub fn reduce_request_is_valid(req : NativeReduceRequest) -> Bool {
  req.element_count > 0 &&
  req.worker_count > 0 &&
  req.chunk_size > 0 &&
  (
    req.value_type == NativeValueType::I32 ||
    req.value_type == NativeValueType::I64
  )
}

///|
pub fn scan_request_is_valid(req : NativeScanRequest) -> Bool {
  req.element_count > 0 &&
  req.worker_count > 0 &&
  req.chunk_size > 0 &&
  req.reduction_kernel == NativeReductionKernel::Sum &&
  (
    req.value_type == NativeValueType::I32 ||
    req.value_type == NativeValueType::I64
  )
}

///|
pub fn map_request_value_type(req : NativeMapRequest) -> Int {
  match req.value_type {
    I32 => 0
    I64 => 1
  }
}

///|
pub fn reduce_request_value_type(req : NativeReduceRequest) -> Int {
  match req.value_type {
    I32 => 0
    I64 => 1
  }
}

///|
pub fn reduce_request_kernel(req : NativeReduceRequest) -> Int {
  match req.reduction_kernel {
    Sum => 0
    Min => 1
    Max => 2
  }
}

///|
pub fn scan_request_value_type(req : NativeScanRequest) -> Int {
  match req.value_type {
    I32 => 0
    I64 => 1
  }
}

///|
pub fn scan_request_kernel(req : NativeScanRequest) -> Int {
  match req.reduction_kernel {
    Sum => 0
    Min => 1
    Max => 2
  }
}

///|
fn request_error_from_issue(
  issue : @plan.ValidationIssue,
) -> NativeRequestError {
  match issue {
    EmptyInput => InvalidArgument
    ChunkSizeDoesNotFitInput(..) => InvalidArgument
    WorkerCountExceedsInput(..) => InvalidArgument
    MissingReductionKernel => UnsupportedReductionKernel
    ScanRequiresStableOrdering => InvalidArgument
    UnsupportedValueType => UnsupportedValueType
    UnsupportedReductionKernel => UnsupportedReductionKernel
    UnsupportedBackend => UnsupportedBackend
    UnsupportedMode => UnsupportedMode
    UnsupportedOrdering(..) => InvalidArgument
  }
}

///|
fn status_code_to_error(code : Int) -> NativeRequestError {
  match code {
    4 => UnsupportedValueType
    5 => UnsupportedReductionKernel
    6 => Overflow
    2 => UnsupportedBackend
    3 => UnsupportedMode
    _ => InvalidArgument
  }
}

///|
fn capability_kind_code(kind : @workflow.CapabilityKind) -> Int {
  match kind {
    OwnedBuffer => 0
    SharedReadView => 1
    AtomicCell => 2
    Mutex => 3
    Condvar => 4
    RwLock => 5
    Semaphore => 6
    Barrier => 7
    Channel => 8
    Opaque(_) => 9
  }
}

///|
fn node_kind_code(kind : @workflow.NodeKind) -> Int {
  match kind {
    Compute(_) => 0
    Spawn => 1
    Join => 2
    Send => 3
    Recv => 4
    Lock => 5
    Unlock => 6
    Wait => 7
    Signal => 8
    Barrier => 9
    ReadShared => 10
    WriteShared => 11
  }
}

///|
fn edge_kind_code(kind : @workflow.EdgeKind) -> Int {
  match kind {
    DataDependency => 0
    ControlDependency => 1
    OwnershipTransfer => 2
    SynchronizationDependency => 3
  }
}

///|
fn workflow_state_from_code(code : Int) -> WorkflowRuntimeState {
  match code {
    0 => Submitted
    1 => Running
    2 => Completed
    3 => Failed
    _ => Rejected
  }
}
