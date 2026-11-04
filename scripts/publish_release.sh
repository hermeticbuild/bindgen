#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/release_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/release_lib.sh"
tag="${1:?usage: publish_release.sh TAG DIRECTORY}"
directory="${2:?usage: publish_release.sh TAG DIRECTORY}"
expected_commit="$(git -C "$repo_root" rev-parse "$tag^{commit}")"
matrix="$("$repo_root/scripts/release_matrix.sh")"
cd "$directory"
shasum -a 256 -c SHA256.txt
jq -e --arg commit "$expected_commit" --argjson matrix "$matrix" '
  .source_commit == $commit and .source_dirty == false and
  ([.variants[] | {workspace,llvm:.llvm_version}] | sort) == ($matrix.include | sort) and
  all(.variants[]; (.artifacts | map(.platform) | sort) ==
    ["darwin_amd64","darwin_arm64","linux_amd64","linux_arm64","windows_amd64","windows_arm64"])
' manifest.json >/dev/null
[[ "$(jq -r '[.variants[].artifacts[].filename] + ["manifest.json"] | sort | .[]' manifest.json)" == "$(awk '{print $2}' SHA256.txt | LC_ALL=C sort)" ]]
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
files=(bindgen_llvm*.tar.zst manifest.json SHA256.txt)
[[ "$(printf '%s\n' "${files[@]}" | LC_ALL=C sort)" == "$(jq -r '[.variants[].artifacts[].filename] + ["manifest.json","SHA256.txt"] | sort | .[]' manifest.json)" ]]
if gh release view "$tag" --json isDraft > "$scratch/release.json" 2>/dev/null; then
  jq -e '.isDraft' "$scratch/release.json" >/dev/null || { echo "refusing to modify published release $tag" >&2; exit 1; }
else
  gh release create "$tag" --verify-tag --draft --title "$tag" --notes-file release-notes.md
fi
# Resume partially uploaded drafts without replacing assets or published releases.
gh release view "$tag" --json assets > "$scratch/assets.json"
for file in "${files[@]}"; do
  expected="sha256:$(shasum -a 256 "$file" | cut -d ' ' -f1)"
  existing="$(jq -r --arg file "$file" '.assets[] | select(.name == $file) | .digest' "$scratch/assets.json")"
  if [[ -n "$existing" ]]; then
    [[ "$existing" == "$expected" ]] || { echo "draft asset differs: $file" >&2; exit 1; }
  else
    gh release upload "$tag" "$file"
  fi
done
gh release view "$tag" --json assets > "$scratch/assets.json"
[[ "$(jq '.assets | length' "$scratch/assets.json")" -eq "${#files[@]}" ]]
for file in "${files[@]}"; do
  jq -e --arg file "$file" --arg digest "sha256:$(shasum -a 256 "$file" | cut -d ' ' -f1)" \
    '.assets[] | select(.name == $file) | .state == "uploaded" and .digest == $digest' "$scratch/assets.json" >/dev/null
done
gh release edit "$tag" --notes-file release-notes.md --draft=false --latest
