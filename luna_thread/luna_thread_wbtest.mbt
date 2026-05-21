///|
test {
  let oversized_chunk = @shared.make_execution_policy(
    worker_count=2,
    chunk_size=64,
  ).unwrap()
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
  assert_eq(issues.length(), 2)
  let has_scan_stable = issues.any(@plan.is_scan_requires_stable_ordering)
  let has_unsupported_ordering = issues.any(@plan.is_unsupported_ordering)
  assert_eq(has_scan_stable, true)
  assert_eq(has_unsupported_ordering, true)
}

///|
test {
  match @shared.make_execution_policy(backend=@shared.javascript_target()) {
    Err({ issue: @shared.UnsupportedBackendForV1(@shared.JavaScript) }) => ()
    _ => panic()
  }
}

///|
test {
  match @shared.make_execution_policy(mode=@shared.asynchronous_mode()) {
    Err({ issue: @shared.UnsupportedModeForV1(@shared.Asynchronous) }) => ()
    _ => panic()
  }
}

///|
test {
  let policy = @shared.make_execution_policy(
    worker_count=4,
    chunk_size=2,
  ).unwrap()
  let plan = @plan.scan("prefix-sum", @plan.i32_type(), 8, policy=policy)
  match @native.scan_request_from_plan(plan) {
    Ok(req) => {
      assert_eq(@native.scan_request_is_valid(req), true)
      assert_eq(@native.scan_request_value_type(req), 0)
      assert_eq(@native.scan_request_kernel(req), 0)
    }
    _ => panic()
  }
}
