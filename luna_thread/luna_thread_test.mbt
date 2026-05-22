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
  let input = FixedArray::make(4, 0)
  input[0] = 1
  input[1] = 2
  input[2] = 3
  input[3] = 4
  match @luna_thread.execute_map_i32(input, worker_count=2, chunk_size=2) {
    Ok(output) => {
      assert_eq(output[0], 2)
      assert_eq(output[1], 4)
      assert_eq(output[2], 6)
      assert_eq(output[3], 8)
    }
    _ => panic()
  }
}

///|
test {
  let input = FixedArray::make(4, 0)
  input[0] = 1
  input[1] = 2
  input[2] = 3
  input[3] = 4
  let reduced = @luna_thread.execute_reduce_sum_i32(
    input,
    worker_count=2,
    chunk_size=2,
  )
  assert_eq(reduced, 10)
}

///|
test {
  let input = FixedArray::make(4, 0)
  input[0] = 1
  input[1] = 2
  input[2] = 3
  input[3] = 4
  match @luna_thread.execute_scan_sum_i32(input, worker_count=2, chunk_size=2) {
    Ok(output) => {
      assert_eq(output[0], 1)
      assert_eq(output[1], 3)
      assert_eq(output[2], 6)
      assert_eq(output[3], 10)
    }
    _ => panic()
  }
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

///|
test {
  let policy = @luna_thread.make_policy(worker_count=2, chunk_size=2).unwrap()
  let compute = @luna_thread.map(
    "double-elements",
    @luna_thread.i32_type(),
    4,
    policy~,
  )
  let workflow = @luna_thread.workflow("pipeline", policy=policy)
    .add_capability(@luna_thread.channel_capability(1, "jobs"))
    .add_node(@luna_thread.spawn_task(1, "spawn"))
    .add_node(@luna_thread.compute_task(2, "compute", compute))
    .add_node(@luna_thread.join_task(3, "join"))
    .add_edge(@workflow.Edge::new(1, 2, @workflow.control_dependency()))
    .add_edge(@workflow.Edge::new(2, 3, @workflow.control_dependency()))
  assert_eq(@luna_thread.workflow_is_ready(workflow), true)
  let submission = @luna_thread.submit_workflow(workflow)
  assert_eq(submission.accepted(), true)
  assert_eq(submission.completed(), false)
}

///|
test {
  let policy = @luna_thread.make_policy(worker_count=2, chunk_size=2).unwrap()
  let workflow = @luna_thread.workflow("async-pipeline", policy=policy)
    .add_capability(@luna_thread.channel_capability(1, "jobs"))
    .add_capability(@luna_thread.mutex_capability(2, "guard"))
    .add_capability(@workflow.Capability::new(
      3,
      "signal",
      @workflow.condvar_capability(),
      @workflow.synchronize_only_access(),
    ))
    .add_capability(@workflow.Capability::new(
      4,
      "barrier",
      @workflow.barrier_capability(),
      @workflow.synchronize_only_access(),
    ))
    .add_node(@luna_thread.spawn_task(1, "spawn"))
    .add_node(@workflow.send_node(2, "send", capability=1))
    .add_node(@workflow.lock_node(3, "lock", capability=2))
    .add_node(@workflow.wait_node(4, "wait", capability=3))
    .add_node(@workflow.signal_node(5, "signal", capability=3))
    .add_node(@workflow.barrier_node(6, "barrier-a", capability=4))
    .add_node(@workflow.barrier_node(7, "barrier-b", capability=4))
    .add_node(@luna_thread.join_task(8, "join"))
    .add_edge(@workflow.Edge::new(1, 2, @workflow.control_dependency()))
    .add_edge(@workflow.Edge::new(2, 3, @workflow.control_dependency()))
    .add_edge(@workflow.Edge::new(3, 4, @workflow.synchronization_dependency()))
    .add_edge(@workflow.Edge::new(3, 5, @workflow.synchronization_dependency()))
    .add_edge(@workflow.Edge::new(4, 6, @workflow.synchronization_dependency()))
    .add_edge(@workflow.Edge::new(5, 7, @workflow.synchronization_dependency()))
    .add_edge(@workflow.Edge::new(6, 8, @workflow.control_dependency()))
    .add_edge(@workflow.Edge::new(7, 8, @workflow.control_dependency()))
  match @luna_thread.submit_workflow_async(workflow) {
    Ok(handle) => {
      let polled = @luna_thread.poll_workflow(handle)
      assert_eq(polled.completed_nodes >= 0, true)
      let waited = @luna_thread.wait_workflow(handle)
      assert_eq(waited.completed_nodes, 8)
      @luna_thread.drop_workflow(handle)
    }
    _ => panic()
  }
}

///|
test {
  let policy = @luna_thread.make_policy(worker_count=2, chunk_size=2).unwrap()
  let workflow = @luna_thread.workflow("broken-barrier", policy=policy)
    .add_capability(@luna_thread.channel_capability(1, "jobs"))
    .add_capability(@luna_thread.mutex_capability(2, "guard"))
    .add_capability(@workflow.Capability::new(
      3,
      "signal",
      @workflow.condvar_capability(),
      @workflow.synchronize_only_access(),
    ))
    .add_capability(@workflow.Capability::new(
      4,
      "barrier",
      @workflow.barrier_capability(),
      @workflow.synchronize_only_access(),
    ))
    .add_node(@luna_thread.spawn_task(1, "spawn"))
    .add_node(@workflow.send_node(2, "send", capability=1))
    .add_node(@workflow.lock_node(3, "lock", capability=2))
    .add_node(@workflow.signal_node(4, "signal", capability=3))
    .add_node(@workflow.barrier_node(5, "barrier", capability=4))
    .add_node(@luna_thread.join_task(6, "join"))
    .add_edge(@workflow.Edge::new(1, 2, @workflow.control_dependency()))
    .add_edge(@workflow.Edge::new(2, 3, @workflow.control_dependency()))
    .add_edge(@workflow.Edge::new(3, 4, @workflow.synchronization_dependency()))
    .add_edge(@workflow.Edge::new(4, 5, @workflow.synchronization_dependency()))
    .add_edge(@workflow.Edge::new(5, 6, @workflow.control_dependency()))
  match @luna_thread.submit_workflow_async(workflow) {
    Ok(handle) => {
      let waited = @luna_thread.wait_workflow(handle)
      assert_eq(waited.status, 14)
      @luna_thread.drop_workflow(handle)
    }
    _ => panic()
  }
}
