# luna_thread

MoonBit parallel FFI specification workspace.

## Repository Layout

- `luna_thread/`: MoonBit library module root
- `luna_thread/moon.mod.json`: MoonBit module metadata
- `luna_thread/luna_thread.mbt`: root MoonBit facade package
- `luna_thread/plan/`, `luna_thread/shared/`, `luna_thread/backend/`: package split for shared types and backend FFI
- `native/`: C runtime and wrapper scaffold
- `js/`: N-API addon scaffold
- `doc/manual/`: documentation sources, published at <https://luna-flow.github.io/en/luna_thread/>
- `doc/attachments/moonbit_parallel_spec/main.typ`: authoritative English specification
- `doc/attachments/moonbit_parallel_spec/main.zh_CN.typ`: Chinese mirror translation
- `doc/attachments/moonbit_parallel_spec/template/`: Typst paper templates
- `docs/spec-review-report-zh.md`: Chinese review notes

## Development Environment

The project stack follows the realization paths defined in the spec:

- `MoonBit facade -> MoonBit C FFI -> C wrapper -> C runtime`
- `MoonBit facade -> MoonBit JS FFI -> JS wrapper -> N-API addon -> C runtime`

So the practical development environment needs:

- MoonBit toolchain: `moon`, `moonc`
- Native toolchain: `clang`, `cmake`, `make`
- JavaScript addon toolchain: `node`, `npm`, `python3`
- Native parallel runtime support: OpenMP headers/runtime
- Optional document toolchain: `typst`

On macOS with Apple clang, OpenMP usually requires `libomp`:

```bash
brew install libomp
```

## Quick Start

Run the environment check:

```bash
./scripts/check-env.sh
```

Include document compilation only when needed:

```bash
CHECK_DOCS=1 ./scripts/check-env.sh
```

Check the MoonBit module:

```bash
make moon-check
```

Configure the native runtime scaffold:

```bash
make native-configure
```

Install and build the JS addon scaffold:

```bash
make js-install
make js-build
```

Build the documentation when needed:

```bash
make docs
```

## Commit Strategy

The specification should be committed in part-sized history slices:

1. English Part I, Part II, Part III
2. Chinese Part I, Part II, Part III as translation commits

Application or proposal drafts are ignored by `.gitignore`.
