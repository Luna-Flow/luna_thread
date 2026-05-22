///|
test {
  let policy = @shared.make_execution_policy(worker_count=4, chunk_size=2).unwrap()
  let compute = @plan.map("double", @plan.i32_type(), 8, policy=policy)
  let graph = Workflow::new("native-graph", policy=policy)
    .add_capability(Capability::new(1, "jobs", channel_capability(), move_only_access()))
    .add_node(spawn_node(1, "spawn"))
    .add_node(compute_node(2, "compute", compute))
    .add_node(join_node(3, "join"))
    .add_edge(Edge::new(1, 2, control_dependency()))
    .add_edge(Edge::new(2, 3, control_dependency()))
  assert_eq(validate(graph).length(), 0)
  let submission = submit(graph)
  assert_eq(submission.accepted(), true)
}

///|
test {
  let graph = Workflow::new("bad-graph")
    .add_node(write_shared_node(1, "write", capability=7))
  let issues = validate(graph)
  assert_eq(issues.any(is_missing_capability), true)
}

///|
test {
  let capability = Capability::new(
    7,
    "opaque",
    opaque_capability("file"),
    read_write_access(),
  )
  let graph = Workflow::new("unsupported")
    .add_capability(capability)
  let issues = validate(graph)
  assert_eq(issues.length() > 0, true)
}

///|
test {
  let policy = @shared.make_execution_policy(worker_count=2, chunk_size=2).unwrap()
  let graph = Workflow::new("cycle", policy=policy)
    .add_node(spawn_node(1, "left"))
    .add_node(join_node(2, "right"))
    .add_edge(Edge::new(1, 2, control_dependency()))
    .add_edge(Edge::new(2, 1, control_dependency()))
  let issues = validate(graph)
  assert_eq(issues.any(is_cyclic_dependency), true)
}
