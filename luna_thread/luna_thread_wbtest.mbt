///|
test {
  let oversized_chunk = @shared.ExecutionPolicy::new(
    worker_count=2,
    chunk_size=64,
  )
  let plan = @plan.map("oversized", @plan.i64_type(), 8, policy=oversized_chunk)
  let issues = @plan.validate(plan)
  assert_eq(issues.length(), 1)
  assert_eq(@plan.is_chunk_size_too_large(issues[0]), true)
  match @native.map_request_from_plan(plan) {
    Err(@native.InvalidArgument) => ()
    _ => panic()
  }
}

///|
test {
  let relaxed_scan = @plan.Plan::new(
    "prefix-sum",
    @plan.scan_plan_kind(),
    @plan.DataDomain::new(@plan.i32_type(), 8),
    ordering=@shared.relaxed_order(),
  )
  let issues = @plan.validate(relaxed_scan)
  assert_eq(issues.length(), 1)
  assert_eq(@plan.is_scan_requires_stable_ordering(issues[0]), true)
}

///|
test {
  let js_policy = @shared.ExecutionPolicy::new(
    backend=@shared.javascript_target(),
  )
  let plan = @plan.map("js-plan", @plan.i32_type(), 4, policy=js_policy)
  match @native.map_request_from_plan(plan) {
    Err(@native.UnsupportedBackend) => ()
    _ => panic()
  }
}

///|
test {
  let async_policy = @shared.ExecutionPolicy::new(
    mode=@shared.asynchronous_mode(),
  )
  let plan = @plan.reduce(
    "async-reduce",
    @plan.i64_type(),
    4,
    @plan.sum_reduction(),
    policy=async_policy,
  )
  match @native.reduce_request_from_plan(plan) {
    Err(@native.UnsupportedMode) => ()
    _ => panic()
  }
}
