#!/usr/bin/env bash
set -euo pipefail

bazel_flags=(--config=remote --lockfile_mode=error)
if [[ -n "${BUILDBUDDY_API_KEY:-}" ]]; then
  bazel_flags+=(
    --remote_header="x-buildbuddy-api-key=${BUILDBUDDY_API_KEY}"
  )
fi

bazel build "${bazel_flags[@]}" //:for_all_platforms

copy_out() {
  local source
  source="$(bazel cquery "${bazel_flags[@]}" --output=files "$1")"
  if [[ ! -f "$source" ]]; then
    echo "expected exactly one output file for $1, got: $source" >&2
    return 1
  fi
  cp -f "$source" "$2"
}

copy_out //:for_aarch64-unknown-linux-musl bindgen_linux_arm64
copy_out //:for_x86_64-unknown-linux-musl bindgen_linux_amd64
copy_out //:for_aarch64-apple-darwin bindgen_darwin_arm64
copy_out //:for_x86_64-apple-darwin bindgen_darwin_amd64
copy_out //:for_aarch64-pc-windows-msvc bindgen_windows_arm64.exe
copy_out //:for_x86_64-pc-windows-msvc bindgen_windows_amd64.exe

artifacts=(
  bindgen_darwin_amd64
  bindgen_darwin_arm64
  bindgen_linux_amd64
  bindgen_linux_arm64
  bindgen_windows_amd64.exe
  bindgen_windows_arm64.exe
)
LC_ALL=C shasum -a 256 "${artifacts[@]}" > SHA256.txt
