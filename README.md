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

To collect the six archives and their checksums in each workspace:

```sh
.github/workflows/build_release.sh 23.1.2
(cd releases/llvm22 && ../../.github/workflows/build_release.sh 22.1.8)
```

`releases/manifest.json` lists the supported variants and supplies the CI matrix.
Keep its versions aligned with the corresponding module manifests.
For example, `bindgen_llvm23.1.2_linux_arm64.tar.zst` runs on Linux ARM64 and
parses headers using Clang 23.1.2. Each archive contains one executable named
`bindgen` or `bindgen.exe`.

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

The same workflow builds both variants before its tag-only release job runs.
It checks the combined checksums, creates a draft, uploads all twelve archives,
`manifest.json`, and `SHA256.txt`, then publishes. The manifest records bindgen
and LLVM versions plus the source commit; checksums cover the archives and manifest.

Creating a release fails if that tag already has one. If an upload fails, inspect
and remove the incomplete draft before rerunning. Releases before this matrix,
including v0.0.3, retain their original names and contents.

Consumers select a release, LLVM variant, and execution platform. Updating
rules_rs's prebuilt selection is a separate consumer change.
