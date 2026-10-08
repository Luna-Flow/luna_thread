# backend/js API

## Purpose

The package `Luna-Flow/luna_thread/backend/js` is the placeholder for the
JavaScript backend. It names its target and nothing more: it declares no
foreign functions and executes nothing. It builds on every target. The
[backend/js design](../../design/backend/js.md) explains why it exists before
the backend does.

## Importing

Add the package, and `shared` and `plan` for the types it returns, to your
`moon.pkg`:

```moonbit nocheck
import {
  "Luna-Flow/luna_thread/backend/js",
  "Luna-Flow/luna_thread/plan",
  "Luna-Flow/luna_thread/shared",
}
```

The example on this page calls them as `@js`, `@plan` and `@shared`.

## Backend information

### `backend_target`

Returns `JavaScript`.

```mbti
pub fn backend_target() -> @shared.BackendTarget
```

### `default_plan_kind`

Returns `Map`, the plan kind the backend would run first.

```mbti
pub fn default_plan_kind() -> @plan.PlanKind
```

### `package_name`

Returns `"backend/js"`.

```mbti
pub fn package_name() -> String
```

```moonbit
test "javascript backend placeholder" {
  assert_true(@js.backend_target() is @shared.JavaScript)
  inspect(@js.package_name(), content="backend/js")
  assert_true(@js.default_plan_kind() is @plan.Map)
}
```
