///|
/// Native backend package. Keep C FFI declarations and native wrapper code here.

pub fn backend_target() -> @shared.BackendTarget {
  @shared.native_target()
}

pub fn package_name() -> String {
  "backend/native"
}

pub fn default_plan_kind() -> @plan.PlanKind {
  @plan.map_plan_kind()
}
