///|
/// Shared types used by facade and backend-specific FFI packages.

pub enum BackendTarget {
  Native
  JavaScript
}

pub fn native_target() -> BackendTarget {
  Native
}

pub fn javascript_target() -> BackendTarget {
  JavaScript
}

pub fn backend_label(target : BackendTarget) -> String {
  match target {
    Native => "native"
    JavaScript => "javascript"
  }
}

pub fn package_name() -> String {
  "shared"
}
