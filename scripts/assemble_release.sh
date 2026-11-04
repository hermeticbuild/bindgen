#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/release_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/release_lib.sh"
input="${1:?usage: assemble_release.sh INPUT OUTPUT}"
output="${2:?usage: assemble_release.sh INPUT OUTPUT}"
matrix="$("$repo_root/scripts/release_matrix.sh")"
commit="$(git -C "$repo_root" rev-parse HEAD)"
platform_json="$(printf '%s\n' "${platforms[@]}" | jq -Rs 'split("\n")[:-1]')"
manifests=()
archives=()
while IFS=$'\t' read -r workspace version; do
  manifest="$input/manifest-llvm${version}.json"
  jq -e --arg commit "$commit" --arg workspace "$workspace" --arg version "$version" --argjson platforms "$platform_json" \
    --arg bindgen "$(bindgen_version "$repo_root/$workspace")" --arg rust "$(rust_version "$repo_root/$workspace")" '
    .schema_version == 1 and .source_commit == $commit and .source_dirty == false and
    .bindgen_version == $bindgen and .rust_version == $rust and
    (.variants | length) == 1 and .variants[0].llvm_version == $version and
    .variants[0].workspace == $workspace and
    (.variants[0].artifacts | map(.platform) | sort) == ($platforms | sort) and
    all(.variants[0].artifacts[];
      .filename == ("bindgen_llvm" + $version + "_" + .platform + ".tar.zst") and
      (.sha256 | test("^[0-9a-f]{64}$")) and (.size > 0))
  ' "$manifest" >/dev/null
  manifests+=("$manifest")
  for platform in "${platforms[@]}"; do
    filename="bindgen_llvm${version}_${platform}.tar.zst"
    expected="$(jq -r --arg filename "$filename" '.variants[0].artifacts[] | select(.filename == $filename) | .sha256' "$manifest")"
    [[ "$(shasum -a 256 "$input/$filename" | cut -d ' ' -f1)" == "$expected" ]]
    [[ "$(wc -c < "$input/$filename" | tr -d ' ')" == "$(jq -r --arg filename "$filename" '.variants[0].artifacts[] | select(.filename == $filename) | .size' "$manifest")" ]]
    archives+=("$filename")
  done
done < <(jq -r '.include[] | [.workspace,.llvm] | @tsv' <<< "$matrix")
jq -se 'map({source_commit,bindgen_version,rust_version,bazel_version}) | unique | length == 1' "${manifests[@]}" >/dev/null
shopt -s nullglob
inputs=("$input"/*)
[[ "${#inputs[@]}" -eq "$((${#manifests[@]} + ${#archives[@]}))" ]] || { echo 'unexpected release inputs' >&2; exit 1; }
mkdir -p "$output"
outputs=("$output"/*)
[[ "${#outputs[@]}" -eq 0 ]] || { echo 'release output directory must be empty' >&2; exit 1; }
# Nothing reaches the publication directory until the complete matrix validates.
for archive in "${archives[@]}"; do cp "$input/$archive" "$output/$archive"; done
jq -sS '.[0] + {variants: (map(.variants[]) | sort_by(.llvm_version))}' "${manifests[@]}" > "$output/manifest.json"
(cd "$output" && LC_ALL=C shasum -a 256 "${archives[@]}" manifest.json > SHA256.txt)
jq -r '"Bindgen " + .bindgen_version + " with statically linked libclang variants:\n\n" +
  ([.variants[] | "- LLVM " + .llvm_version + ": Linux, macOS, Windows; AMD64 and ARM64."] | join("\n")) +
  "\n\nLinux uses musl; Windows uses the static MSVC CRT. Archives contain one executable. Target headers and sysroots are supplied by the consumer.\n\nSource commit: `" + .source_commit + "`. See manifest.json for toolchain versions and checksums."' \
  "$output/manifest.json" > "$output/release-notes.md"
