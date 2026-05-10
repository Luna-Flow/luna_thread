///|
/// JavaScript backend package. Keep JS FFI declarations and host wrapper code here.

pub fn backend_target() -> @shared.BackendTarget {
  @shared.javascript_target()
}

pub fn package_name() -> String {
  "backend/js"
}

pub fn default_plan_kind() -> @plan.PlanKind {
  @plan.map_plan_kind()
}
