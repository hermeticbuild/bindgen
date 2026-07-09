#!/usr/bin/env bash
set -euo pipefail

bazel_flags=(--config=remote --lockfile_mode=error)
if [[ -n "${BUILDBUDDY_API_KEY:-}" ]]; then
  bazel_flags+=(
    --remote_header="x-buildbuddy-api-key=${BUILDBUDDY_API_KEY}"
  )
fi

bazel build "${bazel_flags[@]}" //:release_archives

copy_out() {
  local source
  source="$(bazel cquery "${bazel_flags[@]}" --output=files "$1")"
  if [[ ! -f "$source" ]]; then
    echo "expected exactly one output file for $1, got: $source" >&2
    return 1
  fi
  cp -f "$source" "$2"
}

copy_out //:bindgen_darwin_amd64 bindgen_darwin_amd64.tar.zst
copy_out //:bindgen_darwin_arm64 bindgen_darwin_arm64.tar.zst
copy_out //:bindgen_linux_amd64 bindgen_linux_amd64.tar.zst
copy_out //:bindgen_linux_arm64 bindgen_linux_arm64.tar.zst
copy_out //:bindgen_windows_amd64 bindgen_windows_amd64.tar.zst
copy_out //:bindgen_windows_arm64 bindgen_windows_arm64.tar.zst

artifacts=(
  bindgen_darwin_amd64.tar.zst
  bindgen_darwin_arm64.tar.zst
  bindgen_linux_amd64.tar.zst
  bindgen_linux_arm64.tar.zst
  bindgen_windows_amd64.tar.zst
  bindgen_windows_arm64.tar.zst
)
LC_ALL=C shasum -a 256 "${artifacts[@]}" > SHA256.txt
