# shared tutorial

This tutorial shows you how to build and check execution policies, ask what a
backend declares it can do, and convert native status codes. These are the
values every other package of `luna_thread` takes as input.

## Quick start

Import the package:

```text
import {
  "Luna-Flow/luna_thread/shared",
}
```

Build a policy with four workers and chunks of 256 elements:

```moonbit
test "shared quick start" {
  let policy = @shared.make_execution_policy(worker_count=4, chunk_size=256).unwrap()
  inspect(@shared.backend_label(policy.backend), content="native")
  inspect(@shared.is_parallel(policy), content="true")
}
```

## Everyday tasks

### Handle a rejected policy

`make_execution_policy` returns the first problem it finds, so you can report
it without aborting:

```moonbit
fn describe(result : Result[@shared.ExecutionPolicy, @shared.PolicyError]) -> String {
  match result {
    Ok(policy) => "ok with \{policy.worker_count} workers"
    Err({ issue: WorkerCountMustBePositive(n) }) => "bad worker count \{n}"
    Err({ issue: ChunkSizeMustBePositive(n) }) => "bad chunk size \{n}"
    Err({ issue: UnsupportedBackendForV1(_) }) => "backend not available"
    Err({ issue: UnsupportedModeForV1(_) }) => "mode not available"
  }
}

test "rejected policies" {
  inspect(describe(@shared.make_execution_policy(worker_count=2)), content="ok with 2 workers")
  inspect(describe(@shared.make_execution_policy(chunk_size=0)), content="bad chunk size 0")
  inspect(
    describe(@shared.make_execution_policy(mode=@shared.asynchronous_mode())),
    content="mode not available",
  )
}
```

### Re-check a stored policy

`validate_policy` lists every issue of a policy you already have, for example
one read back from a workflow:

```moonbit
test "validate a stored policy" {
  let policy = @shared.native_policy()
  assert_eq(@shared.validate_policy(policy).length(), 0)
}
```

### Ask what a backend declares

```moonbit
test "capabilities" {
  let native = @shared.RuntimeCapabilities::for_backend(@shared.native_target())
  inspect(native.supports_async, content="false")
  let js = @shared.RuntimeCapabilities::for_backend(@shared.javascript_target())
  inspect(js.supports_zero_copy_buffers, content="true")
}
```

### Convert status codes

```moonbit
test "status codes" {
  let status = @shared.native_status_from_code(6)
  debug_inspect(status, content="Overflow")
  inspect(@shared.native_status_code(status), content="6")
}
```

## Going further

Policies flow into `@plan` builders, `@workflow.Workflow::new` and the facade's
`make_policy`. The integer-coded request records (`NativeBuffer`,
`NativeMapRequest` and the others) mirror the C structs and are useful when you
write your own bindings to the C runtime; the [architecture guide](../architecture.md)
lists the codes.

## Common pitfalls

- `ExecutionPolicy::new` and `javascript_policy` abort on a rejected policy;
  `javascript_policy` always aborts in v1. Use `make_execution_policy` when the
  arguments come from outside.
- `RuntimeCapabilities::for_backend` is a fixed table. The JavaScript row does
  not mean the JavaScript backend runs anything.
- `native_status_from_code` maps every unknown code, including the workflow
  statuses 8 to 14, to `InvalidArgument`. Keep the raw code when you need it.

## Next steps

The [shared API](../api/shared.md) lists every value, and the
[shared design](../design/shared.md) explains the policy rules and the status
code mapping. The [plan tutorial](plan.md) uses policies in plans.
