///|
/// Root library package for the MoonBit facade.
/// Core API stays backend-agnostic; concrete FFI packages live under `backend/`.
pub fn scaffold_status() -> String {
  "luna_thread MoonBit facade"
}

///|
pub fn default_backend() -> @shared.BackendTarget {
  @shared.native_target()
}

///|
pub fn root_plan_package() -> String {
  @plan.package_name()
}

///|
pub fn root_workflow_package() -> String {
  @workflow.package_name()
}

///|
pub fn default_policy() -> @shared.ExecutionPolicy {
  @shared.native_policy()
}

///|
pub fn javascript_policy() -> @shared.ExecutionPolicy {
  @shared.javascript_policy()
}

///|
pub fn make_policy(
  backend? : @shared.BackendTarget = @shared.native_target(),
  mode? : @shared.ExecutionMode = @shared.synchronous_mode(),
  worker_count? : Int = 1,
  chunk_size? : Int = 1,
  ordering? : @shared.OrderingGuarantee = @shared.preserve_input_order(),
) -> Result[@shared.ExecutionPolicy, @shared.PolicyError] {
  @shared.make_execution_policy(
    backend~,
    mode~,
    worker_count~,
    chunk_size~,
    ordering~,
  )
}

///|
pub fn runtime_capabilities(
  backend : @shared.BackendTarget,
) -> @shared.RuntimeCapabilities {
  @shared.RuntimeCapabilities::for_backend(backend)
}

///|
pub fn map(
  label : String,
  element_type : @plan.ValueType,
  input_length : Int,
  policy? : @shared.ExecutionPolicy = default_policy(),
  ordering? : @shared.OrderingGuarantee = @shared.preserve_input_order(),
) -> @plan.Plan {
  @plan.map(label, element_type, input_length, policy~, ordering~)
}

///|
pub fn reduce(
  label : String,
  element_type : @plan.ValueType,
  input_length : Int,
  reduction : @plan.ReductionKernel,
  policy? : @shared.ExecutionPolicy = default_policy(),
) -> @plan.Plan {
  @plan.reduce(label, element_type, input_length, reduction, policy~)
}

///|
pub fn scan(
  label : String,
  element_type : @plan.ValueType,
  input_length : Int,
  policy? : @shared.ExecutionPolicy = default_policy(),
) -> @plan.Plan {
  @plan.scan(label, element_type, input_length, policy~)
}

///|
pub fn map_reduce(
  label : String,
  element_type : @plan.ValueType,
  input_length : Int,
  reduction : @plan.ReductionKernel,
  policy? : @shared.ExecutionPolicy = default_policy(),
  ordering? : @shared.OrderingGuarantee = @shared.preserve_input_order(),
) -> @plan.Plan {
  @plan.map_reduce(
    label,
    element_type,
    input_length,
    reduction,
    policy~,
    ordering~,
  )
}

///|
pub fn validate(plan : @plan.Plan) -> Array[@plan.ValidationIssue] {
  @plan.validate(plan)
}

///|
pub fn workflow(
  label : String,
  policy? : @shared.ExecutionPolicy = default_policy(),
) -> @workflow.Workflow {
  @workflow.Workflow::new(label, policy~)
}

///|
pub fn compute_task(
  id : Int,
  label : String,
  plan : @plan.Plan,
) -> @workflow.Node {
  @workflow.compute_node(id, label, plan)
}

///|
pub fn spawn_task(id : Int, label : String) -> @workflow.Node {
  @workflow.spawn_node(id, label)
}

///|
pub fn join_task(id : Int, label : String) -> @workflow.Node {
  @workflow.join_node(id, label)
}

///|
pub fn channel_capability(
  id : Int,
  label : String,
) -> @workflow.Capability {
  @workflow.Capability::new(
    id,
    label,
    @workflow.channel_capability(),
    @workflow.move_only_access(),
  )
}

///|
pub fn mutex_capability(
  id : Int,
  label : String,
) -> @workflow.Capability {
  @workflow.Capability::new(
    id,
    label,
    @workflow.mutex_capability(),
    @workflow.synchronize_only_access(),
  )
}

///|
pub fn shared_read_capability(
  id : Int,
  label : String,
) -> @workflow.Capability {
  @workflow.Capability::new(
    id,
    label,
    @workflow.shared_read_view_capability(),
    @workflow.read_only_access(),
  )
}

///|
pub fn workflow_validate(
  workflow : @workflow.Workflow,
) -> Array[@workflow.WorkflowIssue] {
  @workflow.validate(workflow)
}

///|
pub fn workflow_is_ready(workflow : @workflow.Workflow) -> Bool {
  @workflow.is_ready(workflow)
}

///|
pub fn submit_workflow(
  workflow : @workflow.Workflow,
  backend? : @shared.BackendTarget = default_backend(),
) -> @workflow.Submission {
  match backend {
    Native => @native.submit_workflow(workflow)
    _ => @workflow.submit(workflow, backend~)
  }
}

///|
pub fn execute_map_i32(
  input : FixedArray[Int],
  worker_count? : Int = 1,
  chunk_size? : Int = 1,
) -> Result[FixedArray[Int], @native.NativeRequestError] {
  @native.execute_map_i32(input, worker_count, chunk_size)
}

///|
pub fn execute_reduce_sum_i32(
  input : FixedArray[Int],
  worker_count? : Int = 1,
  chunk_size? : Int = 1,
) -> Int {
  @native.execute_reduce_sum_i32(input, worker_count, chunk_size)
}

///|
pub fn execute_scan_sum_i32(
  input : FixedArray[Int],
  worker_count? : Int = 1,
  chunk_size? : Int = 1,
) -> Result[FixedArray[Int], @native.NativeRequestError] {
  @native.execute_scan_sum_i32(input, worker_count, chunk_size)
}

///|
pub fn submit_workflow_async(
  workflow : @workflow.Workflow,
) -> Result[@native.WorkflowHandle, @native.NativeRequestError] {
  @native.submit_workflow_async(workflow)
}

///|
pub fn poll_workflow(
  handle : @native.WorkflowHandle,
) -> @native.WorkflowResult {
  @native.poll_workflow(handle)
}

///|
pub fn wait_workflow(
  handle : @native.WorkflowHandle,
) -> @native.WorkflowResult {
  @native.wait_workflow(handle)
}

///|
pub fn drop_workflow(handle : @native.WorkflowHandle) -> Unit {
  @native.drop_workflow(handle)
}

///|
pub fn is_ready(plan : @plan.Plan) -> Bool {
  @plan.is_runnable(plan)
}

///|
pub fn i32_type() -> @plan.ValueType {
  @plan.i32_type()
}

///|
pub fn i64_type() -> @plan.ValueType {
  @plan.i64_type()
}

///|
pub fn f32_type() -> @plan.ValueType {
  @plan.f32_type()
}

///|
pub fn f64_type() -> @plan.ValueType {
  @plan.f64_type()
}

///|
pub fn bytes_type() -> @plan.ValueType {
  @plan.bytes_type()
}

///|
pub fn opaque_type(name : String) -> @plan.ValueType {
  @plan.opaque_type(name)
}

///|
pub fn sum_reduction() -> @plan.ReductionKernel {
  @plan.sum_reduction()
}

///|
pub fn min_reduction() -> @plan.ReductionKernel {
  @plan.min_reduction()
}

///|
pub fn max_reduction() -> @plan.ReductionKernel {
  @plan.max_reduction()
}
