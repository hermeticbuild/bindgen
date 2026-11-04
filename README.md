# bindgen prebuilts

Hermetic `bindgen` 0.72.1 executables for Linux, macOS, and Windows on x86-64
and ARM64. Linux uses musl, Windows uses MSVC with the static CRT, and
LLVM 22.1.8 and 23.1.2 `libclang` variants are linked into separate executables.

## Build

```sh
bazel build --config=remote //:release_archives
# LLVM 22 uses its own module graph and lockfile:
(cd releases/llvm22 && bazel build --config=remote //:release_archives)
```

The root is the current LLVM workspace. `releases/llvm22` has independent
`MODULE.bazel` and `MODULE.bazel.lock` files; symlinks share the BUILD files,
Cargo inputs, flags, and patches. Keep the two module manifests aligned except
for `llvm.version(...)`. Update each lock from its workspace; CI uses
`--lockfile_mode=error`. Windows checkouts need Git symlink support.

`scripts/build_release.sh [WORKSPACE] [OUTPUT]` builds and verifies one variant
with remote execution. `WORKSPACE` defaults to `.` and `OUTPUT` defaults to
`dist/variants`. Run it again with `releases/llvm22` to collect the other variant.
It checks executable architecture, dependencies, the native executable's bindgen
version, and its embedded parser version. It generates Windows x64/ARM64 bindings
from the matching resource headers, including x86/ARM intrinsic headers.
This packaging command runs on Linux
or macOS and requires Bash, jq, zstd, and a tar supporting zstd. Each archive
contains one executable named `bindgen` or `bindgen.exe`.

The workflow matrix is derived from the root and `releases/*/MODULE.bazel`.
For example, `bindgen_llvm23.1.2_linux_arm64.tar.zst` runs on Linux ARM64 and
parses headers using Clang 23.1.2; its target architecture is selected by the
consumer's Clang arguments.

## Use

The executables do not include target headers or a sysroot. Pass the selected
C/C++ toolchain's Clang arguments and, when no separate Clang executable is
available, `--no-include-path-detection`.

## Release

```sh
./release.sh v0.0.4
```

The release tag identifies the packaging revision. Bindgen's version and each
exact LLVM version are independent dimensions recorded in `manifest.json`.
Tag a reviewed commit on `master` after both CI variants pass.

The tag workflow builds both variants, then validates all twelve archives before
creating or resuming a draft release. It uploads the twelve versioned archives,
`manifest.json`, and `SHA256.txt`, verifies GitHub's uploaded asset digests, and
only then publishes. Existing published releases are never overwritten. A retry
can resume an incomplete draft if its existing asset digests match.

`manifest.json` records the source commit, bindgen/Rust/Bazel versions, each
workspace's module and lock hashes, and artifact names, sizes, and SHA256 hashes.
Dirty source builds are marked in their metadata and cannot be assembled or
published. The publisher also requires the tag to point to the manifest's commit.
The combined checksum file covers all archives and the manifest. Releases before
this matrix, including v0.0.3, retain their original names and contents.

Run `scripts/test_release.sh` for the release assembly acceptance tests. Publishing
requires `gh` authenticated for the repository; CI supplies `GH_TOKEN` and
`GH_REPO`. Consumers must explicitly select a release, LLVM variant, and execution
platform. Updating rules_rs's prebuilt selection is a separate consumer change.
