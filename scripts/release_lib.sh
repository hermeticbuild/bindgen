#!/usr/bin/env bash
# Shared release inputs; MODULE.bazel remains the source of LLVM selection.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
platforms=(darwin_amd64 darwin_arm64 linux_amd64 linux_arm64 windows_amd64 windows_arm64)

llvm_version() {
  local version
  version="$(sed -n 's/^llvm.version(llvm_version = "\([^"]*\)")$/\1/p' "$1/MODULE.bazel")"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "expected one explicit llvm.version in $1/MODULE.bazel" >&2
    return 1
  fi
  printf '%s\n' "$version"
}

rust_version() {
  sed -n 's/^    version = "\([^"]*\)",$/\1/p' "$1/MODULE.bazel" | tail -1
}

bindgen_version() {
  awk '/^name = "bindgen"$/ {found=1; next} found && /^version = / {gsub(/"/, "", $3); print $3; exit}' "$1/Cargo.lock"
}
