///|
/// Root library package for the MoonBit facade.
/// Core API stays backend-agnostic; concrete FFI packages live under `backend/`.

pub fn scaffold_status() -> String {
  "luna_thread library scaffold"
}

pub fn default_backend() -> @shared.BackendTarget {
  @shared.native_target()
}

pub fn root_plan_package() -> String {
  @plan.package_name()
}
