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
