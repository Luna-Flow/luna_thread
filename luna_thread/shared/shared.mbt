///|
/// Shared domain types used by facade and backend-specific FFI packages.
pub enum BackendTarget {
  Native
  JavaScript
} derive(Eq, Debug)

///|
pub enum NativeStatus {
  Ok
  InvalidArgument
  UnsupportedBackend
  UnsupportedMode
  UnsupportedValueType
  UnsupportedReductionKernel
  Overflow
  NullPointer
} derive(Eq, Debug)

///|
pub enum ExecutionMode {
  Synchronous
  Asynchronous
} derive(Eq, Debug)

///|
pub enum OrderingGuarantee {
  PreserveInputOrder
  RelaxedOrder
} derive(Eq, Debug)

///|
pub enum PolicyIssue {
  WorkerCountMustBePositive(Int)
  ChunkSizeMustBePositive(Int)
  UnsupportedBackendForV1(BackendTarget)
  UnsupportedModeForV1(ExecutionMode)
} derive(Eq, Debug)

///|
pub struct ExecutionPolicy {
  backend : BackendTarget
  mode : ExecutionMode
  worker_count : Int
  chunk_size : Int
  ordering : OrderingGuarantee
} derive(Eq, Debug)

///|
pub struct PolicyError {
  issue : PolicyIssue
} derive(Eq, Debug)

///|
pub struct RuntimeCapabilities {
  backend : BackendTarget
  supports_parallelism : Bool
  supports_async : Bool
  supports_zero_copy_buffers : Bool
} derive(Eq, Debug)

///|
pub struct NativeBuffer {
  ptr : Int
  length : Int
} derive(Eq, Debug)

///|
pub struct NativeMapRequest {
  input : NativeBuffer
  output : NativeBuffer
  element_count : Int
  value_type : Int
  worker_count : Int
  chunk_size : Int
} derive(Eq, Debug)

///|
pub struct NativeReduceRequest {
  input : NativeBuffer
  output : NativeBuffer
  element_count : Int
  value_type : Int
  reduction_kernel : Int
  worker_count : Int
  chunk_size : Int
} derive(Eq, Debug)

///|
pub struct NativeScanRequest {
  input : NativeBuffer
  output : NativeBuffer
  element_count : Int
  value_type : Int
  reduction_kernel : Int
  worker_count : Int
  chunk_size : Int
} derive(Eq, Debug)

///|
pub fn native_target() -> BackendTarget {
  Native
}

///|
pub fn javascript_target() -> BackendTarget {
  JavaScript
}

///|
pub fn synchronous_mode() -> ExecutionMode {
  Synchronous
}

///|
pub fn asynchronous_mode() -> ExecutionMode {
  Asynchronous
}

///|
pub fn preserve_input_order() -> OrderingGuarantee {
  PreserveInputOrder
}

///|
pub fn relaxed_order() -> OrderingGuarantee {
  RelaxedOrder
}

///|
pub fn ExecutionPolicy::new(
  backend? : BackendTarget = Native,
  mode? : ExecutionMode = Synchronous,
  worker_count? : Int = 1,
  chunk_size? : Int = 1,
  ordering? : OrderingGuarantee = PreserveInputOrder,
) -> ExecutionPolicy {
  make_execution_policy(backend~, mode~, worker_count~, chunk_size~, ordering~).unwrap()
}

///|
pub fn native_policy() -> ExecutionPolicy {
  make_execution_policy().unwrap()
}

///|
pub fn javascript_policy() -> ExecutionPolicy {
  make_execution_policy(backend=JavaScript).unwrap()
}

///|
pub fn RuntimeCapabilities::for_backend(
  backend : BackendTarget,
) -> RuntimeCapabilities {
  match backend {
    Native =>
      {
        backend,
        supports_parallelism: true,
        supports_async: false,
        supports_zero_copy_buffers: false,
      }
    JavaScript =>
      {
        backend,
        supports_parallelism: true,
        supports_async: true,
        supports_zero_copy_buffers: true,
      }
  }
}

///|
pub fn validate_policy(policy : ExecutionPolicy) -> Array[PolicyIssue] {
  let issues = []
  if policy.worker_count <= 0 {
    issues.push(WorkerCountMustBePositive(policy.worker_count))
  }
  if policy.chunk_size <= 0 {
    issues.push(ChunkSizeMustBePositive(policy.chunk_size))
  }
  if policy.backend != Native {
    issues.push(UnsupportedBackendForV1(policy.backend))
  }
  if policy.mode != Synchronous {
    issues.push(UnsupportedModeForV1(policy.mode))
  }
  issues
}

///|
pub fn make_execution_policy(
  backend? : BackendTarget = Native,
  mode? : ExecutionMode = Synchronous,
  worker_count? : Int = 1,
  chunk_size? : Int = 1,
  ordering? : OrderingGuarantee = PreserveInputOrder,
) -> Result[ExecutionPolicy, PolicyError] {
  if worker_count <= 0 {
    return Err({ issue: WorkerCountMustBePositive(worker_count) })
  }
  if chunk_size <= 0 {
    return Err({ issue: ChunkSizeMustBePositive(chunk_size) })
  }
  if backend != Native {
    return Err({ issue: UnsupportedBackendForV1(backend) })
  }
  if mode != Synchronous {
    return Err({ issue: UnsupportedModeForV1(mode) })
  }
  Ok({ backend, mode, worker_count, chunk_size, ordering })
}

///|
pub fn is_parallel(policy : ExecutionPolicy) -> Bool {
  policy.worker_count > 1
}

///|
pub fn backend_label(target : BackendTarget) -> String {
  match target {
    Native => "native"
    JavaScript => "javascript"
  }
}

///|
pub fn package_name() -> String {
  "shared"
}

///|
pub fn native_status_code(status : NativeStatus) -> Int {
  match status {
    Ok => 0
    InvalidArgument => 1
    UnsupportedBackend => 2
    UnsupportedMode => 3
    UnsupportedValueType => 4
    UnsupportedReductionKernel => 5
    Overflow => 6
    NullPointer => 7
  }
}

///|
pub fn native_status_from_code(code : Int) -> NativeStatus {
  match code {
    0 => Ok
    1 => InvalidArgument
    2 => UnsupportedBackend
    3 => UnsupportedMode
    4 => UnsupportedValueType
    5 => UnsupportedReductionKernel
    6 => Overflow
    7 => NullPointer
    _ => InvalidArgument
  }
}

///|
pub fn NativeBuffer::new(ptr : Int, length : Int) -> NativeBuffer {
  { ptr, length }
}

///|
pub fn NativeBuffer::ptr(self : NativeBuffer) -> Int {
  self.ptr
}

///|
pub fn NativeBuffer::length(self : NativeBuffer) -> Int {
  self.length
}

///|
pub fn NativeMapRequest::new(
  input : NativeBuffer,
  output : NativeBuffer,
  element_count : Int,
  value_type : Int,
  worker_count : Int,
  chunk_size : Int,
) -> NativeMapRequest {
  { input, output, element_count, value_type, worker_count, chunk_size }
}

///|
pub fn NativeReduceRequest::new(
  input : NativeBuffer,
  output : NativeBuffer,
  element_count : Int,
  value_type : Int,
  reduction_kernel : Int,
  worker_count : Int,
  chunk_size : Int,
) -> NativeReduceRequest {
  {
    input,
    output,
    element_count,
    value_type,
    reduction_kernel,
    worker_count,
    chunk_size,
  }
}

///|
pub fn NativeScanRequest::new(
  input : NativeBuffer,
  output : NativeBuffer,
  element_count : Int,
  value_type : Int,
  reduction_kernel : Int,
  worker_count : Int,
  chunk_size : Int,
) -> NativeScanRequest {
  {
    input,
    output,
    element_count,
    value_type,
    reduction_kernel,
    worker_count,
    chunk_size,
  }
}

///|
pub fn NativeMapRequest::input(self : NativeMapRequest) -> NativeBuffer {
  self.input
}

///|
pub fn NativeMapRequest::output(self : NativeMapRequest) -> NativeBuffer {
  self.output
}

///|
pub fn NativeMapRequest::element_count(self : NativeMapRequest) -> Int {
  self.element_count
}

///|
pub fn NativeMapRequest::value_type(self : NativeMapRequest) -> Int {
  self.value_type
}

///|
pub fn NativeMapRequest::worker_count(self : NativeMapRequest) -> Int {
  self.worker_count
}

///|
pub fn NativeMapRequest::chunk_size(self : NativeMapRequest) -> Int {
  self.chunk_size
}

///|
pub fn NativeReduceRequest::input(self : NativeReduceRequest) -> NativeBuffer {
  self.input
}

///|
pub fn NativeReduceRequest::output(self : NativeReduceRequest) -> NativeBuffer {
  self.output
}

///|
pub fn NativeReduceRequest::element_count(self : NativeReduceRequest) -> Int {
  self.element_count
}

///|
pub fn NativeReduceRequest::value_type(self : NativeReduceRequest) -> Int {
  self.value_type
}

///|
pub fn NativeReduceRequest::reduction_kernel(self : NativeReduceRequest) -> Int {
  self.reduction_kernel
}

///|
pub fn NativeReduceRequest::worker_count(self : NativeReduceRequest) -> Int {
  self.worker_count
}

///|
pub fn NativeReduceRequest::chunk_size(self : NativeReduceRequest) -> Int {
  self.chunk_size
}

///|
pub fn NativeScanRequest::input(self : NativeScanRequest) -> NativeBuffer {
  self.input
}

///|
pub fn NativeScanRequest::output(self : NativeScanRequest) -> NativeBuffer {
  self.output
}

///|
pub fn NativeScanRequest::element_count(self : NativeScanRequest) -> Int {
  self.element_count
}

///|
pub fn NativeScanRequest::value_type(self : NativeScanRequest) -> Int {
  self.value_type
}

///|
pub fn NativeScanRequest::reduction_kernel(self : NativeScanRequest) -> Int {
  self.reduction_kernel
}

///|
pub fn NativeScanRequest::worker_count(self : NativeScanRequest) -> Int {
  self.worker_count
}

///|
pub fn NativeScanRequest::chunk_size(self : NativeScanRequest) -> Int {
  self.chunk_size
}
