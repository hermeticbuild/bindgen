#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/release_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/release_lib.sh"
shopt -s nullglob
modules=("$repo_root/MODULE.bazel" "$repo_root"/releases/*/MODULE.bazel)
for module in "${modules[@]}"; do
  workspace="$(dirname "$module")"
  relative="${workspace#"$repo_root"}"
  jq -nc --arg workspace "${relative#/}" --arg llvm "$(llvm_version "$workspace")" \
    '{workspace: (if $workspace == "" then "." else $workspace end), llvm: $llvm}'
done | jq -sce '
  if (map(.llvm) | unique | length) == length then {include: .}
  else error("duplicate LLVM versions in release workspaces") end'
