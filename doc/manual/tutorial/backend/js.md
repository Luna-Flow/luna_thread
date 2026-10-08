# backend/js tutorial

This short tutorial shows what the JavaScript backend package offers today and
how to write code that is ready for it: the package names the JavaScript
target, and the rest of the module already describes JavaScript policies and
capabilities, but nothing executes on JavaScript yet.

## Quick start

Import the package; it builds on every target:

```text
import {
  "Luna-Flow/luna_thread/backend/js",
}
```

```moonbit
test "js quick start" {
  inspect(@shared.backend_label(@js.backend_target()), content="javascript")
}
```

## Everyday tasks

### Select a backend by target

Code that chooses a backend at run time can use each backend package's
`backend_target`:

```moonbit
fn backend_for(prefer_js : Bool) -> @shared.BackendTarget {
  if prefer_js {
    @js.backend_target()
  } else {
    @shared.native_target()
  }
}

test "select" {
  inspect(@shared.backend_label(backend_for(true)), content="javascript")
}
```

### Check what the JavaScript backend would accept

Validation tells you that v1 rejects the JavaScript backend, so you can fall
back to the native one:

```moonbit
test "rejected" {
  let result = @shared.make_execution_policy(backend=@js.backend_target())
  assert_true(result is Err({ issue: UnsupportedBackendForV1(JavaScript) }))
  let graph = @workflow.Workflow::new("one").add_node(
    @workflow.spawn_node(1, "spawn"),
  )
  inspect(
    @workflow.submit(graph, backend=@js.backend_target()).accepted(),
    content="false",
  )
}
```

## Going further

The specification describes a JavaScript realization that passes typed array
buffers to a Node.js addon. The addon in `js/` is built with `make js-install`
and `make js-build` and currently exports only `runtimeName`; the
[architecture guide](../../architecture.md) describes it.

## Common pitfalls

- Do not call `@shared.javascript_policy()`: it aborts in v1.
- `RuntimeCapabilities::for_backend(JavaScript)` declares async and zero-copy
  support that does not exist yet.

## Next steps

The [backend/js API](../../api/backend/js.md) lists the three functions, and
the [backend/js design](../../design/backend/js.md) explains why the package
exists before the backend does.
