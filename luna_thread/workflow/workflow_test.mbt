///|
test {
  let policy = @shared.make_execution_policy(worker_count=4, chunk_size=2).unwrap()
  let compute = @plan.map("double", @plan.i32_type(), 8, policy~)
  let graph = @workflow.Workflow::new("native-graph", policy~)
    .add_capability(
      @workflow.Capability::new(
        1,
        "jobs",
        @workflow.channel_capability(),
        @workflow.move_only_access(),
      ),
    )
    .add_node(@workflow.spawn_node(1, "spawn"))
    .add_node(@workflow.compute_node(2, "compute", compute))
    .add_node(@workflow.join_node(3, "join"))
    .add_edge(@workflow.Edge::new(1, 2, @workflow.control_dependency()))
    .add_edge(@workflow.Edge::new(2, 3, @workflow.control_dependency()))
  assert_eq(@workflow.validate(graph).length(), 0)
  let submission = @workflow.submit(graph)
  assert_eq(submission.accepted(), true)
}

///|
test {
  let graph = @workflow.Workflow::new("bad-graph").add_node(
    @workflow.write_shared_node(1, "write", capability=7),
  )
  let issues = @workflow.validate(graph)
  assert_eq(issues.any(@workflow.is_missing_capability), true)
}

///|
test {
  let capability = @workflow.Capability::new(
    7,
    "opaque",
    @workflow.opaque_capability("file"),
    @workflow.read_write_access(),
  )
  let graph = @workflow.Workflow::new("unsupported").add_capability(capability)
  let issues = @workflow.validate(graph)
  assert_eq(issues.length() > 0, true)
}

///|
test {
  let policy = @shared.make_execution_policy(worker_count=2, chunk_size=2).unwrap()
  let graph = @workflow.Workflow::new("cycle", policy~)
    .add_node(@workflow.spawn_node(1, "left"))
    .add_node(@workflow.join_node(2, "right"))
    .add_edge(@workflow.Edge::new(1, 2, @workflow.control_dependency()))
    .add_edge(@workflow.Edge::new(2, 1, @workflow.control_dependency()))
  let issues = @workflow.validate(graph)
  assert_eq(issues.any(@workflow.is_cyclic_dependency), true)
}
