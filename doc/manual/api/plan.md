# plan API

The package `Luna-Flow/luna_thread/plan`, imported as `@plan`, describes one
data-parallel operation as a value: its kind, the element type and length of
its input, the execution policy, an optional reduction kernel and an ordering
guarantee. It validates plans against the v1 subset. It executes nothing and
builds on every target.

The enumerations of this package are read-only outside it: match on their
constructors, but build values with the functions below.

## Types

### `PlanKind`

The four operations a plan can describe.

```mbti
pub enum PlanKind {
  Map
  Reduce
  Scan
  MapReduce
} derive(Eq, @debug.Debug)
```

`Map` applies a function to every element, `Reduce` combines all elements with
a kernel, `Scan` produces the running combination (prefix), and `MapReduce`
maps and then reduces.

### `ValueType`

The element type of a plan's input.

```mbti
pub enum ValueType {
  I32
  I64
  F32
  F64
  Bytes
  Opaque(String)
} derive(Eq, @debug.Debug)
```

Only `I32` and `I64` are supported in v1.

### `ReductionKernel`

The binary operation of a reduce, map-reduce or scan.

```mbti
pub enum ReductionKernel {
  Sum
  Min
  Max
  Custom(String)
} derive(Eq, @debug.Debug)
```

`Custom(name)` names a kernel that the runtime does not know; it never passes
validation in v1.

### `DataDomain`

The element type and length of a plan's input.

```mbti
pub struct DataDomain {
  element_type : ValueType
  input_length : Int
} derive(Eq, @debug.Debug)
pub fn DataDomain::new(ValueType, Int) -> Self
pub fn DataDomain::element_type(Self) -> ValueType
pub fn DataDomain::input_length(Self) -> Int
```

`DataDomain::new(t, n)` stores its arguments unchecked; `validate` rejects
$n \le 0$.

### `Plan`

A complete plan.

```mbti
pub struct Plan {
  label : String
  kind : PlanKind
  domain : DataDomain
  policy : @shared.ExecutionPolicy
  reduction : ReductionKernel?
  ordering : @shared.OrderingGuarantee
} derive(Eq, @debug.Debug)
pub fn Plan::new(String, PlanKind, DataDomain, policy? : @shared.ExecutionPolicy, reduction? : ReductionKernel, ordering? : @shared.OrderingGuarantee) -> Self
```

`Plan::new` stores its arguments unchecked. `policy` defaults to
`@shared.native_policy()`, `reduction` to `None` and `ordering` to
`PreserveInputOrder`. Use it for combinations the builders below do not make,
such as a scan with relaxed ordering.

### `Plan::label`, `Plan::kind`, `Plan::domain`, `Plan::policy`, `Plan::reduction` and `Plan::ordering`

Return the fields of a plan.

```mbti
pub fn Plan::label(Self) -> String
pub fn Plan::kind(Self) -> PlanKind
pub fn Plan::domain(Self) -> DataDomain
pub fn Plan::policy(Self) -> @shared.ExecutionPolicy
pub fn Plan::reduction(Self) -> ReductionKernel?
pub fn Plan::ordering(Self) -> @shared.OrderingGuarantee
```

### `ValidationIssue`

One reason why a plan is outside the v1 subset.

```mbti
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
  UnsupportedOrdering(kind~ : PlanKind, ordering~ : @shared.OrderingGuarantee)
} derive(Eq, @debug.Debug)
```

`validate` describes when each one is reported.

### `T::equal`

Structural equality, promoted as a method on every type of the package:
`DataDomain`, `Plan`, `PlanKind`, `ReductionKernel`, `ValidationIssue` and
`ValueType`. Use `==` and `!=`.

```mbti
pub fn Plan::equal(Self, Self) -> Bool
```

## Constructors for enumerations

### `map_plan_kind`, `reduce_plan_kind`, `scan_plan_kind` and `map_reduce_plan_kind`

Return `Map`, `Reduce`, `Scan` and `MapReduce`.

```mbti
pub fn map_plan_kind() -> PlanKind
pub fn reduce_plan_kind() -> PlanKind
pub fn scan_plan_kind() -> PlanKind
pub fn map_reduce_plan_kind() -> PlanKind
```

### `i32_type`, `i64_type`, `f32_type`, `f64_type`, `bytes_type` and `opaque_type`

Return `I32`, `I64`, `F32`, `F64`, `Bytes` and `Opaque(name)`.

```mbti
pub fn i32_type() -> ValueType
pub fn i64_type() -> ValueType
pub fn f32_type() -> ValueType
pub fn f64_type() -> ValueType
pub fn bytes_type() -> ValueType
pub fn opaque_type(String) -> ValueType
```

### `sum_reduction`, `min_reduction`, `max_reduction` and `custom_reduction`

Return `Sum`, `Min`, `Max` and `Custom(name)`.

```mbti
pub fn sum_reduction() -> ReductionKernel
pub fn min_reduction() -> ReductionKernel
pub fn max_reduction() -> ReductionKernel
pub fn custom_reduction(String) -> ReductionKernel
```

```moonbit
test "enumeration constructors" {
  assert_true(@plan.scan_plan_kind() is @plan.Scan)
  debug_inspect(@plan.opaque_type("rgba"), content="Opaque(\"rgba\")")
  debug_inspect(@plan.custom_reduction("xor"), content="Custom(\"xor\")")
}
```

## Building plans

### `map`

Builds a `Map` plan.

```mbti
pub fn map(String, ValueType, Int, policy? : @shared.ExecutionPolicy, ordering? : @shared.OrderingGuarantee) -> Plan
```

The arguments are the label, the element type and the input length; `policy`
defaults to `@shared.native_policy()` and `ordering` to `PreserveInputOrder`.
The reduction is `None`.

### `reduce`

Builds a `Reduce` plan with a reduction kernel and `PreserveInputOrder`.

```mbti
pub fn reduce(String, ValueType, Int, ReductionKernel, policy? : @shared.ExecutionPolicy) -> Plan
```

### `scan`

Builds a `Scan` plan with `PreserveInputOrder` and no reduction kernel.

```mbti
pub fn scan(String, ValueType, Int, policy? : @shared.ExecutionPolicy) -> Plan
```

The native scan kernel is a prefix sum, so a scan plan does not name its
kernel.

### `map_reduce`

Builds a `MapReduce` plan.

```mbti
pub fn map_reduce(String, ValueType, Int, ReductionKernel, policy? : @shared.ExecutionPolicy, ordering? : @shared.OrderingGuarantee) -> Plan
```

```moonbit
test "building plans" {
  let policy = @shared.make_execution_policy(worker_count=2, chunk_size=4).unwrap()
  let plan = @plan.reduce("min", @plan.i64_type(), 8, @plan.min_reduction(), policy~)
  assert_true(plan.kind() is @plan.Reduce)
  assert_eq(plan.domain().input_length(), 8)
  assert_eq(plan.reduction(), Some(@plan.min_reduction()))
}
```

## Validation

### `validate`

Returns every issue of a plan, in a fixed order, or an empty array.

```mbti
pub fn validate(Plan) -> Array[ValidationIssue]
```

With $n$ the input length, $w$ the worker count and $c$ the chunk size of the
policy, the checks are:

| Issue | Reported when |
| --- | --- |
| `EmptyInput` | $n \le 0$ |
| `UnsupportedValueType` | the element type is not `I32` or `I64` |
| `ChunkSizeDoesNotFitInput` | $c > n > 0$ |
| `WorkerCountExceedsInput` | $w > n > 0$ |
| `UnsupportedBackend` | the policy's backend is not `Native` |
| `UnsupportedMode` | the policy's mode is not `Synchronous` |
| `MissingReductionKernel` | a `Reduce` or `MapReduce` plan has no kernel |
| `UnsupportedReductionKernel` | the kernel of a `Reduce` or `MapReduce` plan is `Custom` |
| `UnsupportedOrdering` and `ScanRequiresStableOrdering` | a `Scan` plan has `RelaxedOrder`; both are reported |

`validate` does not check the cover condition $w \ge \lceil n / c \rceil$ that
the native kernels also require.

### `is_runnable`

Returns `true` when `validate` returns no issue.

```mbti
pub fn is_runnable(Plan) -> Bool
```

### `value_type_is_supported_in_v1`, `reduction_kernel_is_supported_in_v1` and `ordering_is_valid_for_kind`

The individual v1 rules used by `validate`.

```mbti
pub fn value_type_is_supported_in_v1(ValueType) -> Bool
pub fn reduction_kernel_is_supported_in_v1(ReductionKernel) -> Bool
pub fn ordering_is_valid_for_kind(PlanKind, @shared.OrderingGuarantee) -> Bool
```

The first accepts `I32` and `I64`, the second `Sum`, `Min` and `Max`. The
third accepts every ordering except `RelaxedOrder` for `Scan`.

```moonbit
test "validation" {
  let relaxed = @plan.Plan::new(
    "prefix",
    @plan.scan_plan_kind(),
    @plan.DataDomain::new(@plan.i32_type(), 8),
    ordering=@shared.relaxed_order(),
  )
  let issues = @plan.validate(relaxed)
  assert_eq(issues.length(), 2)
  assert_true(issues[0] is @plan.UnsupportedOrdering(kind=@plan.Scan, ..))
  assert_true(issues[1] is @plan.ScanRequiresStableOrdering)
  assert_true(!@plan.is_runnable(relaxed))
  assert_true(!@plan.reduction_kernel_is_supported_in_v1(@plan.custom_reduction("xor")))
}
```

## Predicates

### `is_map`, `is_reduce`, `is_scan` and `is_map_reduce`

Test the kind of a plan.

```mbti
pub fn is_map(Plan) -> Bool
pub fn is_reduce(Plan) -> Bool
pub fn is_scan(Plan) -> Bool
pub fn is_map_reduce(Plan) -> Bool
```

### `has_sum_reduction`

Returns `true` when the plan's kernel is `Some(Sum)`.

```mbti
pub fn has_sum_reduction(Plan) -> Bool
```

### `is_chunk_size_too_large`, `is_scan_requires_stable_ordering`, `is_unsupported_value_type`, `is_unsupported_reduction_kernel`, `is_unsupported_backend`, `is_unsupported_mode` and `is_unsupported_ordering`

Test which issue a `ValidationIssue` is, for use with `Array::any`.

```mbti
pub fn is_chunk_size_too_large(ValidationIssue) -> Bool
pub fn is_scan_requires_stable_ordering(ValidationIssue) -> Bool
pub fn is_unsupported_value_type(ValidationIssue) -> Bool
pub fn is_unsupported_reduction_kernel(ValidationIssue) -> Bool
pub fn is_unsupported_backend(ValidationIssue) -> Bool
pub fn is_unsupported_mode(ValidationIssue) -> Bool
pub fn is_unsupported_ordering(ValidationIssue) -> Bool
```

`is_chunk_size_too_large` matches `ChunkSizeDoesNotFitInput`; the others match
the issue of the same name.

```moonbit
test "issue predicates" {
  let policy = @shared.make_execution_policy(chunk_size=64).unwrap()
  let plan = @plan.map("small", @plan.i32_type(), 8, policy~)
  let issues = @plan.validate(plan)
  assert_true(issues.any(@plan.is_chunk_size_too_large))
  assert_true(@plan.is_map(plan) && !@plan.has_sum_reduction(plan))
}
```

## Package information

### `package_name` and `default_backend_label`

Return `"plan"` and the label of the default backend, `"native"`.

```mbti
pub fn package_name() -> String
pub fn default_backend_label() -> String
```
