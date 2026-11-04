#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/release_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/release_lib.sh"
workspace="${1:-.}"
output="${2:-$repo_root/dist/variants}"
scripts_matrix="$("$repo_root/scripts/release_matrix.sh")"
jq -e --arg workspace "$workspace" '.include[] | select(.workspace == $workspace)' <<< "$scripts_matrix" >/dev/null
mkdir -p "$output"
output="$(cd "$output" && pwd)"
cd "$repo_root/$workspace"
version="$(llvm_version "$PWD")"
source_commit="$(git -C "$repo_root" rev-parse HEAD)"
source_dirty=false
[[ -z "$(git -C "$repo_root" status --porcelain)" ]] || source_dirty=true
flags=(--config=remote --lockfile_mode=error)
if [[ -n "${BUILDBUDDY_API_KEY:-}" ]]; then
  flags+=(--remote_header="x-buildbuddy-api-key=${BUILDBUDDY_API_KEY}")
fi
bazel_command=(bazel)
if [[ -n "${BINDGEN_OUTPUT_BASE:-}" ]]; then
  bazel_command+=(--output_base="$BINDGEN_OUTPUT_BASE")
fi
"${bazel_command[@]}" build "${flags[@]}" //:release_archives @llvm//tools:llvm-readobj
execution_root="$("${bazel_command[@]}" info "${flags[@]}" execution_root)"
reader="$execution_root/$("${bazel_command[@]}" cquery "${flags[@]}" --output=files @llvm//tools:llvm-readobj)"
[[ -f "$reader" ]]
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
entries=()
for platform in "${platforms[@]}"; do
  binary=bindgen
  [[ "$platform" != windows_* ]] || binary=bindgen.exe
  archive="bindgen_llvm${version}_${platform}.tar.zst"
  source_archive="$execution_root/$("${bazel_command[@]}" cquery "${flags[@]}" --output=files "//:bindgen_$platform")"
  [[ -f "$source_archive" ]]
  [[ "$(tar -tf "$source_archive")" == "$binary" ]]
  mkdir "$scratch/$platform"
  tar -xf "$source_archive" -C "$scratch/$platform"
  inspection="$("$reader" --file-headers --program-headers --needed-libs --coff-imports "$scratch/$platform/$binary")"
  if [[ "$platform" == *_amd64 ]]; then
    grep -q 'Arch: x86_64' <<< "$inspection"
  else
    grep -Eq 'Arch: (aarch64|arm64)' <<< "$inspection"
  fi
  case "$platform" in
    linux_*)
      if grep -Eq 'Type: (PT_)?INTERP|^[[:space:]]+[^[:space:]]+\.so' <<< "$inspection"; then
        echo "unexpected dynamic dependency in $platform" >&2; exit 1
      fi ;;
    windows_*)
      if grep -Eiq 'Name: .*(libclang|msvcrt|ucrtbase|vcruntime|msvcp|api-ms-win-crt)' <<< "$inspection"; then
        echo "unexpected libclang or CRT DLL in $platform" >&2; exit 1
      fi ;;
    darwin_*)
      if grep -Eiq 'libclang.*dylib' <<< "$inspection"; then
        echo "unexpected libclang dylib in $platform" >&2; exit 1
      fi ;;
  esac
  cp -f "$source_archive" "$output/$archive"
  chmod u+w "$output/$archive"
  entries+=("$(jq -nc --arg platform "$platform" --arg filename "$archive" \
    --arg sha256 "$(shasum -a 256 "$output/$archive" | cut -d ' ' -f1)" \
    --argjson size "$(wc -c < "$output/$archive")" \
    '{platform:$platform,filename:$filename,sha256:$sha256,size:$size}')")
done

case "$(uname -s):$(uname -m)" in
  Linux:x86_64) native=linux_amd64 ;;
  Linux:aarch64|Linux:arm64) native=linux_arm64 ;;
  Darwin:x86_64) native=darwin_amd64 ;;
  Darwin:arm64) native=darwin_arm64 ;;
  *) echo 'release smoke checks require a Linux or macOS host' >&2; exit 1 ;;
esac
executable="$scratch/$native/bindgen"
actual_bindgen="$("$executable" --version)"
actual_bindgen="${actual_bindgen#bindgen }"
[[ "$actual_bindgen" == "$(bindgen_version "$PWD")" ]]
resources="$(dirname "$reader")/../lib/clang/${version%%.*}/include"
for target in x86_64-pc-windows-msvc aarch64-pc-windows-msvc; do
  "$executable" --no-include-path-detection --formatter=none --no-layout-tests \
    --allowlist-type bindgen_probe --allowlist-var 'parser_.*' \
    "$repo_root/tests/parser.h" --output "$scratch/version.rs" -- \
    --target="$target" -ffreestanding -nostdinc -isystem "$resources"
  grep -q 'pub struct bindgen_probe' "$scratch/version.rs"
  actual="$(for part in major minor patch; do printf '%s\n' "$(sed -n "s/.*parser_${part}[^=]*= *\([0-9][0-9]*\) *.*/\1/p" "$scratch/version.rs")"; done | paste -sd . -)"
  [[ "$actual" == "$version" ]] || { echo "expected parser $version, got $actual" >&2; exit 1; }
done
if [[ -n "$(git -C "$repo_root" status --porcelain)" || "$(git -C "$repo_root" rev-parse HEAD)" != "$source_commit" ]]; then
  source_dirty=true
fi
printf '%s\n' "${entries[@]}" | jq -s \
  --argjson source_dirty "$source_dirty" \
  --arg source_commit "$source_commit" --arg bindgen_version "$actual_bindgen" \
  --arg rust_version "$(rust_version "$PWD")" --arg bazel_version "$(bazel --version | cut -d ' ' -f2)" \
  --arg llvm_version "$version" --arg workspace "$workspace" \
  --arg module_sha256 "$(shasum -a 256 MODULE.bazel | cut -d ' ' -f1)" \
  --arg lock_sha256 "$(shasum -a 256 MODULE.bazel.lock | cut -d ' ' -f1)" \
  '{schema_version:1,source_commit:$source_commit,source_dirty:$source_dirty,bindgen_version:$bindgen_version,rust_version:$rust_version,bazel_version:$bazel_version,
    variants:[{llvm_version:$llvm_version,workspace:$workspace,module_sha256:$module_sha256,lock_sha256:$lock_sha256,artifacts:.}]}' \
  > "$output/manifest-llvm${version}.json"
