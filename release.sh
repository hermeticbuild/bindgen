#!/usr/bin/env bash
set -euo pipefail

version="${1:?usage: release.sh VERSION}"
git tag -a "$version" -m "$version"
git push origin "$version"
