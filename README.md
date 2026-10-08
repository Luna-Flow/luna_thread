# luna_thread

`luna_thread` lets MoonBit programs describe parallel work as data, plans for
map, reduce and scan and workflow graphs of synchronising tasks, validate it in
MoonBit, and run integer kernels and workflow graphs on a native C runtime
through the foreign function interface. A normative specification in
`doc/attachments/` defines where the library is heading; version 0.1.0
implements a first subset of it on the native target.

## Install

```text
moon add Luna-Flow/luna_thread@0.1.0
```

Import `"Luna-Flow/luna_thread"` in a package's `moon.pkg` and build for the
native target (`supported_targets = "native"` or `--target native`).

## Example

```moonbit
test "sum in parallel chunks" {
  let input : FixedArray[Int] = [1, 2, 3, 4, 5, 6]
  let total = @luna_thread.execute_reduce_sum_i32(
    input,
    worker_count=2,
    chunk_size=3,
  )
  inspect(total, content="21")
}
```

## Packages

The MoonBit module lives in the `luna_thread/` directory.

| Package | Targets | Contents |
| --- | --- | --- |
| `Luna-Flow/luna_thread` | native | The facade: policies, plan and workflow builders, kernels, asynchronous workflows. |
| `Luna-Flow/luna_thread/plan` | all | Data-parallel plans and their validation. |
| `Luna-Flow/luna_thread/workflow` | all | Task graphs with capabilities and their validation. |
| `Luna-Flow/luna_thread/shared` | all | Execution policies, backend targets, status codes and C record mirrors. |
| `Luna-Flow/luna_thread/backend/native` | native | C FFI backend: kernels, workflow runtime, typed requests. |
| `Luna-Flow/luna_thread/backend/js` | all | Placeholder for the JavaScript backend. |

Outside the module, `native/` holds the C runtime with a CMake build and smoke
test, and `js/` a Node.js addon scaffold.

## Status

- Only the native backend in synchronous mode passes validation.
- The kernels double, sum, take the minimum or maximum of, and prefix-sum
  `Int` and `Int64` arrays with overflow checking.
- Workflow graphs run on a pthread scheduler; compute nodes do not yet execute
  their plans, and the asynchronous path has a known memory-lifetime defect
  that makes it crash intermittently. The
  [native backend design](doc/manual/design/backend/native.md) lists the known
  defects.
- The JavaScript backend and addon are scaffolds.

## Requirements

- MoonBit `moonc` 0.10 or later and a C compiler for the native target.
- Optional: CMake and OpenMP (`libomp` on macOS) for the standalone C runtime,
  Node.js, npm and Python for the addon, and Typst for the specification.

`./scripts/check-env.sh` checks the toolchain. The `Makefile` provides
`moon-check`, `native-configure`, `native-build`, `js-install`, `js-build` and
`docs`.

## Documentation

The manual is published at <https://lunaflow.cn/en/luna_thread/> and its
source starts at [`doc/manual/index.md`](doc/manual/index.md), with an API,
tutorial and design page for every package, an
[architecture guide](doc/manual/architecture.md), and Chinese and Japanese
translations. Start with the [core tutorial](doc/manual/tutorial/core.md).
`docs/spec-review-report-zh.md` is an earlier review of the specification,
kept as a historical record. The specification is
`doc/attachments/moonbit_parallel_spec/main.typ`, with a Chinese mirror in
`main.zh_CN.typ`.

## Contributing

Use English [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
Run `moon -C luna_thread fmt`, `moon -C luna_thread check --target all`, `moon -C luna_thread info`
and `moon -C luna_thread test --target native` before a pull request, and keep
`native/src/runtime.c` and `luna_thread/backend/native/ffi_runtime_impl.c`
identical apart from the include path. Specification changes follow
[AGENT_GUIDE.md](AGENT_GUIDE.md): English first, then the Chinese mirror.

## License

Apache-2.0. See [LICENSE](LICENSE).
