///|
/// Plan-layer package for backend-agnostic parallel plan data.
pub enum PlanKind {
  Map
  Reduce
  Scan
  MapReduce
} derive(Eq, Debug)

///|
pub enum ValueType {
  I32
  I64
  F32
  F64
  Bytes
  Opaque(String)
} derive(Eq, Debug)

///|
pub enum ReductionKernel {
  Sum
  Min
  Max
  Custom(String)
} derive(Eq, Debug)

///|
pub enum ValidationIssue {
  EmptyInput
  ChunkSizeDoesNotFitInput(chunk_size~ : Int, input_length~ : Int)
  WorkerCountExceedsInput(worker_count~ : Int, input_length~ : Int)
  MissingReductionKernel
  ScanRequiresStableOrdering
  UnsupportedValueType
  UnsupportedReductionKernel
  UnsupportedBackend
  UnsupportedMode
} derive(Eq, Debug)

///|
pub struct DataDomain {
  element_type : ValueType
  input_length : Int
} derive(Eq, Debug)

///|
pub struct Plan {
  label : String
  kind : PlanKind
  domain : DataDomain
  policy : @shared.ExecutionPolicy
  reduction : ReductionKernel?
  ordering : @shared.OrderingGuarantee
} derive(Eq, Debug)

///|
pub fn map_plan_kind() -> PlanKind {
  Map
}

///|
pub fn reduce_plan_kind() -> PlanKind {
  Reduce
}

///|
pub fn scan_plan_kind() -> PlanKind {
  Scan
}

///|
pub fn map_reduce_plan_kind() -> PlanKind {
  MapReduce
}

///|
pub fn i32_type() -> ValueType {
  I32
}

///|
pub fn i64_type() -> ValueType {
  I64
}

///|
pub fn f32_type() -> ValueType {
  F32
}

///|
pub fn f64_type() -> ValueType {
  F64
}

///|
pub fn bytes_type() -> ValueType {
  Bytes
}

///|
pub fn opaque_type(name : String) -> ValueType {
  Opaque(name)
}

///|
pub fn sum_reduction() -> ReductionKernel {
  Sum
}

///|
pub fn min_reduction() -> ReductionKernel {
  Min
}

///|
pub fn max_reduction() -> ReductionKernel {
  Max
}

///|
pub fn custom_reduction(name : String) -> ReductionKernel {
  Custom(name)
}

///|
pub fn DataDomain::new(
  element_type : ValueType,
  input_length : Int,
) -> DataDomain {
  { element_type, input_length }
}

///|
pub fn Plan::new(
  label : String,
  kind : PlanKind,
  domain : DataDomain,
  policy? : @shared.ExecutionPolicy = @shared.native_policy(),
  reduction? : ReductionKernel,
  ordering? : @shared.OrderingGuarantee = @shared.preserve_input_order(),
) -> Plan {
  { label, kind, domain, policy, reduction, ordering }
}

///|
pub fn map(
  label : String,
  element_type : ValueType,
  input_length : Int,
  policy? : @shared.ExecutionPolicy = @shared.native_policy(),
  ordering? : @shared.OrderingGuarantee = @shared.preserve_input_order(),
) -> Plan {
  Plan::new(
    label,
    Map,
    DataDomain::new(element_type, input_length),
    policy~,
    ordering~,
  )
}

///|
pub fn reduce(
  label : String,
  element_type : ValueType,
  input_length : Int,
  reduction : ReductionKernel,
  policy? : @shared.ExecutionPolicy = @shared.native_policy(),
) -> Plan {
  Plan::new(
    label,
    Reduce,
    DataDomain::new(element_type, input_length),
    policy~,
    reduction~,
  )
}

///|
pub fn scan(
  label : String,
  element_type : ValueType,
  input_length : Int,
  policy? : @shared.ExecutionPolicy = @shared.native_policy(),
) -> Plan {
  Plan::new(
    label,
    Scan,
    DataDomain::new(element_type, input_length),
    policy~,
    ordering=@shared.preserve_input_order(),
  )
}

///|
pub fn map_reduce(
  label : String,
  element_type : ValueType,
  input_length : Int,
  reduction : ReductionKernel,
  policy? : @shared.ExecutionPolicy = @shared.native_policy(),
  ordering? : @shared.OrderingGuarantee = @shared.preserve_input_order(),
) -> Plan {
  Plan::new(
    label,
    MapReduce,
    DataDomain::new(element_type, input_length),
    policy~,
    reduction~,
    ordering~,
  )
}

///|
pub fn validate(plan : Plan) -> Array[ValidationIssue] {
  let issues = []
  if plan.domain.input_length <= 0 {
    issues.push(EmptyInput)
  }
  if plan.policy.chunk_size > plan.domain.input_length &&
    plan.domain.input_length > 0 {
    issues.push(
      ChunkSizeDoesNotFitInput(
        chunk_size=plan.policy.chunk_size,
        input_length=plan.domain.input_length,
      ),
    )
  }
  if plan.policy.worker_count > plan.domain.input_length &&
    plan.domain.input_length > 0 {
    issues.push(
      WorkerCountExceedsInput(
        worker_count=plan.policy.worker_count,
        input_length=plan.domain.input_length,
      ),
    )
  }
  match plan.kind {
    Reduce | MapReduce =>
      if plan.reduction == None {
        issues.push(MissingReductionKernel)
      }
    Scan =>
      if plan.ordering != @shared.preserve_input_order() {
        issues.push(ScanRequiresStableOrdering)
      }
    _ => ()
  }
  issues
}

///|
pub fn is_runnable(plan : Plan) -> Bool {
  validate(plan).length() == 0
}

///|
pub fn is_map(plan : Plan) -> Bool {
  plan.kind == Map
}

///|
pub fn is_reduce(plan : Plan) -> Bool {
  plan.kind == Reduce
}

///|
pub fn is_scan(plan : Plan) -> Bool {
  plan.kind == Scan
}

///|
pub fn is_map_reduce(plan : Plan) -> Bool {
  plan.kind == MapReduce
}

///|
pub fn has_sum_reduction(plan : Plan) -> Bool {
  plan.reduction == Some(Sum)
}

///|
pub fn is_chunk_size_too_large(issue : ValidationIssue) -> Bool {
  match issue {
    ChunkSizeDoesNotFitInput(..) => true
    _ => false
  }
}

///|
pub fn is_scan_requires_stable_ordering(issue : ValidationIssue) -> Bool {
  match issue {
    ScanRequiresStableOrdering => true
    _ => false
  }
}

///|
pub fn is_unsupported_value_type(issue : ValidationIssue) -> Bool {
  match issue {
    UnsupportedValueType => true
    _ => false
  }
}

///|
pub fn is_unsupported_reduction_kernel(issue : ValidationIssue) -> Bool {
  match issue {
    UnsupportedReductionKernel => true
    _ => false
  }
}

///|
pub fn is_unsupported_backend(issue : ValidationIssue) -> Bool {
  match issue {
    UnsupportedBackend => true
    _ => false
  }
}

///|
pub fn is_unsupported_mode(issue : ValidationIssue) -> Bool {
  match issue {
    UnsupportedMode => true
    _ => false
  }
}

///|
pub fn package_name() -> String {
  "plan"
}

///|
pub fn default_backend_label() -> String {
  @shared.backend_label(@shared.native_target())
}

///|
pub fn Plan::label(self : Plan) -> String {
  self.label
}

///|
pub fn Plan::kind(self : Plan) -> PlanKind {
  self.kind
}

///|
pub fn Plan::domain(self : Plan) -> DataDomain {
  self.domain
}

///|
pub fn Plan::policy(self : Plan) -> @shared.ExecutionPolicy {
  self.policy
}

///|
pub fn Plan::reduction(self : Plan) -> ReductionKernel? {
  self.reduction
}

///|
pub fn Plan::ordering(self : Plan) -> @shared.OrderingGuarantee {
  self.ordering
}

///|
pub fn DataDomain::element_type(self : DataDomain) -> ValueType {
  self.element_type
}

///|
pub fn DataDomain::input_length(self : DataDomain) -> Int {
  self.input_length
}
