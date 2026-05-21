///|
test {
  let policy = @luna_thread.make_policy().unwrap()
  let plan = @luna_thread.map(
    "double-elements",
    @luna_thread.i32_type(),
    16,
    policy~,
  )
  assert_eq(@plan.is_map(plan), true)
  assert_eq(plan.domain.input_length, 16)
  assert_eq(@luna_thread.is_ready(plan), true)
}

///|
test {
  match @luna_thread.make_policy(worker_count=-3, chunk_size=0) {
    Err({ issue: @shared.WorkerCountMustBePositive(-3) }) => ()
    _ => panic()
  }
}

///|
test {
  let policy = @luna_thread.make_policy(worker_count=4, chunk_size=8).unwrap()
  let plan = @luna_thread.map_reduce(
    "sum-elements",
    @luna_thread.i64_type(),
    32,
    @luna_thread.sum_reduction(),
    policy~,
  )
  assert_eq(@plan.has_sum_reduction(plan), true)
  assert_eq(@luna_thread.validate(plan).length(), 0)
}
