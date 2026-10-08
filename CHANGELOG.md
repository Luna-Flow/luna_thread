# Changelog

All notable changes to this repository are recorded here. Versions follow
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- The initial plan, workflow, shared and backend packages, the native C runtime
  with OpenMP kernels and a pthread workflow scheduler, the Node.js addon
  scaffold, and the normative specification.

### Changed

- Require MoonBit `moonc` 0.10: the module manifest moved from `moon.mod.json`
  to `moon.mod`, and the package manifests use the `moon.pkg` syntax.
- Trait methods are promoted explicitly through `extends.mbt` in `shared`,
  `plan`, `workflow` and `backend/native`: `equal` stays a method of every
  public type; `not_equal` and `to_repr` remain as deprecated, hidden methods
  (use `!=` and `Debug::to_repr`).
- The facade and `backend/native` declare `supported_targets = "native"`, so
  `moon check --target all` succeeds; `plan`, `shared`, `workflow` and
  `backend/js` build on every target.
- Regenerated `pkg.generated.mbti` files now list the previously unrecorded
  public functions: the `execute_*` kernels, `submit_workflow_async`,
  `poll_workflow`, `wait_workflow`, `drop_workflow` and the raw `ffi_*`
  declarations.
- Blackbox tests qualify names from the package under test.
- Documentation rewritten: one API, tutorial and design page per package
  (`core`, `plan`, `workflow`, `shared`, `backend/native`, `backend/js`)
  replacing the `facade` and `backend` pages, a new architecture guide, and
  zh_CN and ja_JP translations.

### Known issues

- The C bridge frees a workflow's request while its worker threads still read
  it, so asynchronous workflow runs (and the test suite) crash intermittently.
- Blocked `Send`, `Recv` and `Lock` workflow nodes are never retried.
- `javascript_policy()` aborts, and `execute_reduce_sum_i32` reports failures
  as `0`.
