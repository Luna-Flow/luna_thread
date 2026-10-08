# plan tutorial

This tutorial gets you describing a data-parallel operation as a `Plan`,
checking it against the v1 subset, and reading the reasons when a plan is
rejected. Plans are plain data, so everything here works on every target.

| I want to | Use |
| --- | --- |
| describe doubling, a reduction, a prefix sum or both | `@plan.map`, `@plan.reduce`, `@plan.scan`, `@plan.map_reduce` |
| run the plan with several workers | a policy from `@shared.make_execution_policy`, passed as `policy~` |
| know whether v1 supports a plan | `@plan.is_runnable(plan)` |
| show every problem of a plan | `@plan.validate(plan)` and the `is_*` issue predicates |
| build a combination the builders refuse | `@plan.Plan::new` |

## Quick start

Add the module, then import the package, and `shared` for policies:

```bash
moon add Luna-Flow/luna_thread@0.1.0
```

```moonbit nocheck
import {
  "Luna-Flow/luna_thread/plan",
  "Luna-Flow/luna_thread/shared",
}
```

Build a map plan over eight `Int` values and validate it:

```moonbit
test "plan quick start" {
  let plan = @plan.map("double", @plan.i32_type(), 8)
  inspect(@plan.is_runnable(plan), content="true")
  inspect(plan.label(), content="double")
}
```

## Everyday tasks

### Give a plan a policy

The default policy uses one worker and chunk size one. Build a parallel policy
with `make_execution_policy` and pass it to the builder:

```moonbit
test "policy" {
  let policy = @shared.make_execution_policy(worker_count=4, chunk_size=16).unwrap()
  let plan = @plan.map_reduce("sum", @plan.i64_type(), 64, @plan.sum_reduction(), policy~)
  assert_eq(plan.policy().worker_count, 4)
  assert_true(@plan.has_sum_reduction(plan))
  assert_true(@plan.is_runnable(plan))
}
```

### Read why a plan is rejected

`validate` returns all problems at once, so you can report them together:

```moonbit
test "issues" {
  let policy = @shared.make_execution_policy(worker_count=8, chunk_size=8).unwrap()
  let plan = @plan.reduce("tiny", @plan.f32_type(), 4, @plan.custom_reduction("xor"), policy~)
  let issues = @plan.validate(plan)
  assert_true(issues.any(@plan.is_unsupported_value_type))
  assert_true(issues.any(@plan.is_chunk_size_too_large))
  assert_true(issues.any(@plan.is_unsupported_reduction_kernel))
  assert_eq(issues.length(), 4)
}
```

The fourth issue is `WorkerCountExceedsInput`: eight workers for four
elements.

### Build an unusual plan by hand

`Plan::new` stores whatever you give it, which is how you test validation
rules such as the ordering requirement of scans:

```moonbit
test "relaxed scan" {
  let plan = @plan.Plan::new(
    "prefix",
    @plan.scan_plan_kind(),
    @plan.DataDomain::new(@plan.i32_type(), 8),
    ordering=@shared.relaxed_order(),
  )
  let issues = @plan.validate(plan)
  assert_true(issues.any(@plan.is_unsupported_ordering))
  assert_true(issues.any(@plan.is_scan_requires_stable_ordering))
}
```

### Inspect a plan

Accessors return each field, and the kind predicates save a match:

```moonbit
test "inspect" {
  let plan = @plan.scan("prefix", @plan.i64_type(), 32)
  assert_true(@plan.is_scan(plan))
  assert_eq(plan.reduction(), None)
  assert_true(plan.ordering() is @shared.PreserveInputOrder)
  assert_eq(plan.domain().input_length(), 32)
}
```

## Going further

Plans become executable through `backend/native`, whose
`map_request_from_plan`, `reduce_request_from_plan` and
`scan_request_from_plan` turn a valid plan into a typed request, and through
workflows, where `@workflow.compute_node` embeds a plan in a task graph and
`@workflow.validate` reports its issues as `InvalidComputePlan`. Write
library code against `Plan` and `ValidationIssue` rather than against the
facade, so it builds for every target.

## Common pitfalls

- `is_runnable` does not check that there is one worker per chunk
  ($w \ge \lceil n / c \rceil$), which the native kernels require.
- `reduce` and `scan` always preserve input order; to try other orderings use
  `Plan::new`.
- A scan plan has no kernel; the native scan is always a prefix sum, and a
  kernel stored in a scan or map plan with `Plan::new` is neither checked nor
  used.
- The enumerations are read-only outside the package: write
  `@plan.i32_type()`, not `@plan.I32`, when you build a value. Matching on
  `@plan.I32` works.

## Next steps

The [plan API](../api/plan.md) lists every rule of `validate`. The
[plan design](../design/plan.md) explains what each plan kind computes and why
scans need ordered input. The [workflow tutorial](workflow.md) puts plans into
task graphs.
