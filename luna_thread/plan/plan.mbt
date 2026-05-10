///|
/// Plan-layer package for backend-agnostic parallel plan data.

pub enum PlanKind {
  Map
  Reduce
  Scan
  MapReduce
}

pub fn map_plan_kind() -> PlanKind {
  Map
}

pub fn reduce_plan_kind() -> PlanKind {
  Reduce
}

pub fn scan_plan_kind() -> PlanKind {
  Scan
}

pub fn map_reduce_plan_kind() -> PlanKind {
  MapReduce
}

pub fn package_name() -> String {
  "plan"
}

pub fn default_backend_label() -> String {
  @shared.backend_label(@shared.native_target())
}
