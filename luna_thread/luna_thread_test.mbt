///|
test {
  let plan = @luna_thread.map("double-elements", @luna_thread.i32_type(), 16)
  assert_eq(@plan.is_map(plan), true)
  assert_eq(plan.domain.input_length, 16)
  assert_eq(@luna_thread.is_ready(plan), true)
}

///|
test {
  let policy = @shared.ExecutionPolicy::new(worker_count=-3, chunk_size=0)
  assert_eq(policy.worker_count, 1)
  assert_eq(policy.chunk_size, 1)
}

///|
test {
  let plan = @luna_thread.map_reduce(
    "sum-elements",
    @luna_thread.f64_type(),
    32,
    @luna_thread.sum_reduction(),
    policy=@shared.ExecutionPolicy::new(worker_count=4, chunk_size=8),
  )
  assert_eq(@plan.has_sum_reduction(plan), true)
  assert_eq(@luna_thread.validate(plan).length(), 0)
}
