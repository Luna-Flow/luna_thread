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
pub fn default_policy() -> @shared.ExecutionPolicy {
  @shared.native_policy()
}

///|
pub fn javascript_policy() -> @shared.ExecutionPolicy {
  @shared.javascript_policy()
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
