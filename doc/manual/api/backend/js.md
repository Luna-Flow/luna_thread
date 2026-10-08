# backend/js API

The package `Luna-Flow/luna_thread/backend/js`, imported as `@js`, is the
placeholder for the JavaScript backend. It names its target and nothing more:
it declares no foreign functions and executes nothing. It builds on every
target.

## `backend_target`

Returns `JavaScript`.

```mbti
pub fn backend_target() -> @shared.BackendTarget
```

## `default_plan_kind`

Returns `Map`, the plan kind the backend would run first.

```mbti
pub fn default_plan_kind() -> @plan.PlanKind
```

## `package_name`

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
