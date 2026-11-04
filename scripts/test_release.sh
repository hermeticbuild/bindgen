#!/usr/bin/env bash
# Exercise release assembly through its CLI with real archives and checksums.
set -euo pipefail
# shellcheck source=scripts/release_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/release_lib.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/good" "$scratch/bin"
printf '#!/bin/sh\nexit 0\n' > "$scratch/bin/bindgen"
cp "$scratch/bin/bindgen" "$scratch/bin/bindgen.exe"
chmod +x "$scratch/bin/"*
commit="$(git -C "$repo_root" rev-parse HEAD)"
while IFS=$'\t' read -r workspace version; do
  entries=()
  for platform in "${platforms[@]}"; do
    executable=bindgen
    [[ "$platform" != windows_* ]] || executable=bindgen.exe
    filename="bindgen_llvm${version}_${platform}.tar.zst"
    tar -cf - -C "$scratch/bin" "$executable" | zstd -q -c > "$scratch/good/$filename"
    entries+=("$(jq -nc --arg filename "$filename" --arg platform "$platform" \
      --arg sha256 "$(shasum -a 256 "$scratch/good/$filename" | cut -d ' ' -f1)" \
      --argjson size "$(wc -c < "$scratch/good/$filename")" \
      '{filename:$filename,platform:$platform,sha256:$sha256,size:$size}')")
  done
  printf '%s\n' "${entries[@]}" | jq -s --arg commit "$commit" --arg workspace "$workspace" --arg version "$version" \
    '{schema_version:1,source_commit:$commit,source_dirty:false,bindgen_version:"0.72.1",rust_version:"1.96.1",bazel_version:"9.1.0",
      variants:[{llvm_version:$version,workspace:$workspace,artifacts:.}]}' > "$scratch/good/manifest-llvm${version}.json"
done < <("$repo_root/scripts/release_matrix.sh" | jq -r '.include[] | [.workspace,.llvm] | @tsv')

"$repo_root/scripts/assemble_release.sh" "$scratch/good" "$scratch/complete"
jq -e '(.variants | length) == 2 and ([.variants[].artifacts[]] | length) == 12' "$scratch/complete/manifest.json" >/dev/null
(cd "$scratch/complete" && shasum -a 256 -c SHA256.txt >/dev/null)
echo 'PASS: complete twelve-archive matrix assembles with verified checksums'

reject() {
  local scenario="$1"
  if "$repo_root/scripts/assemble_release.sh" "$scratch/$scenario" "$scratch/$scenario-output" > "$scratch/$scenario.log" 2>&1; then
    echo "FAIL: accepted $scenario" >&2; exit 1
  fi
  [[ ! -e "$scratch/$scenario-output/manifest.json" ]]
  echo "PASS: rejects $scenario before assembling release"
}

mkdir "$scratch/missing-variant"
cp "$scratch/good/"*llvm23.1.2* "$scratch/missing-variant/"
reject missing-variant

cp -R "$scratch/good" "$scratch/mixed-commits"
jq '.source_commit = "different-commit"' "$scratch/good/manifest-llvm22.1.8.json" > "$scratch/mixed-commits/manifest-llvm22.1.8.json"
reject mixed-commits

cp -R "$scratch/good" "$scratch/dirty-sources"
jq '.source_dirty = true' "$scratch/good/manifest-llvm22.1.8.json" > "$scratch/dirty-sources/manifest-llvm22.1.8.json"
reject dirty-sources

cp -R "$scratch/good" "$scratch/corrupted-archive"
printf 'corruption' >> "$scratch/corrupted-archive/bindgen_llvm22.1.8_linux_arm64.tar.zst"
reject corrupted-archive

cp -R "$scratch/good" "$scratch/wrong-parser-version"
jq '.variants[0].llvm_version = "23.1.2"' "$scratch/good/manifest-llvm22.1.8.json" > "$scratch/wrong-parser-version/manifest-llvm22.1.8.json"
reject wrong-parser-version

cp -R "$scratch/good" "$scratch/unexpected-artifact"
cp "$scratch/good/bindgen_llvm22.1.8_linux_arm64.tar.zst" "$scratch/unexpected-artifact/extra.tar.zst"
reject unexpected-artifact
