#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

status_ok() {
  printf '[ok] %s\n' "$1"
}

status_warn() {
  printf '[warn] %s\n' "$1"
}

check_cmd() {
  local name="$1"
  local version_cmd="$2"

  if command -v "$name" >/dev/null 2>&1; then
    status_ok "$name: $($version_cmd 2>/dev/null | head -n 1)"
  else
    status_warn "$name: missing"
  fi
}

check_typst_build() {
  local src="$1"
  local out
  out="$(mktemp /tmp/luna-thread-typst-XXXXXX.pdf)"
  if typst compile "$src" "$out" >/dev/null 2>&1; then
    status_ok "typst compile: $(basename "$src")"
    rm -f "$out"
  else
    status_warn "typst compile failed: $(basename "$src")"
    rm -f "$out"
  fi
}

check_docs_if_requested() {
  if [[ "${CHECK_DOCS:-0}" == "1" ]]; then
    check_typst_build "docs/moonbit-parallel-spec-en.typ"
    check_typst_build "docs/moonbit-parallel-spec-zh.typ"
  else
    status_ok "typst compile: skipped (set CHECK_DOCS=1 to enable)"
  fi
}

check_openmp() {
  local src bin
  src="$(mktemp /tmp/luna-thread-omp-XXXXXX.c)"
  bin="$(mktemp /tmp/luna-thread-omp-XXXXXX)"

  cat >"$src" <<'EOF'
#include <omp.h>
#include <stdio.h>

int main(void) {
  int n = 0;
  #pragma omp parallel reduction(+:n)
  n += 1;
  printf("%d\n", n);
  return 0;
}
EOF

  if clang -Xpreprocessor -fopenmp -I/opt/homebrew/opt/libomp/include -L/opt/homebrew/opt/libomp/lib -lomp "$src" -o "$bin" >/dev/null 2>&1; then
    status_ok "OpenMP: clang + libomp available"
    rm -f "$src" "$bin"
  else
    status_warn "OpenMP: missing headers/runtime for clang; install libomp if native parallel runtime work starts"
    rm -f "$src" "$bin"
  fi
}

cd "$ROOT_DIR"

printf 'Repository: %s\n' "$ROOT_DIR"

check_cmd typst "typst --version"
check_cmd moon "moon version"
check_cmd moonc "moonc -v"
check_cmd node "node --version"
check_cmd npm "npm --version"
check_cmd clang "clang --version"
check_cmd cmake "cmake --version"
check_cmd make "make --version"
check_cmd python3 "python3 --version"
check_cmd git "git --version"

if moon -C luna_thread check >/dev/null 2>&1; then
  status_ok "moon check: module is loadable"
else
  status_warn "moon check failed: verify MoonBit module setup"
fi

if cmake -S native -B /tmp/luna-thread-native-check >/dev/null 2>&1; then
  status_ok "cmake configure: native scaffold"
  rm -rf /tmp/luna-thread-native-check
else
  status_warn "cmake configure failed: native scaffold"
  rm -rf /tmp/luna-thread-native-check
fi

if node -p 'process.versions.napi' >/dev/null 2>&1; then
  status_ok "node napi: $(node -p 'process.versions.napi')"
else
  status_warn "node napi: unavailable"
fi

if [[ -x "js/node_modules/.bin/node-gyp" ]]; then
  status_ok "node-gyp: $(js/node_modules/.bin/node-gyp --version)"
elif command -v node-gyp >/dev/null 2>&1; then
  status_ok "node-gyp: $(node-gyp --version)"
else
  status_warn "node-gyp: missing; run npm install in js/ before addon builds"
fi

check_openmp
check_docs_if_requested
