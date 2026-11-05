# bindgen prebuilts

Hermetic `bindgen` 0.73.2 executables for Linux, macOS, and Windows on x86-64
and ARM64. Linux uses musl, Windows uses MSVC with the static CRT, and
LLVM 23.1.2 `libclang` is linked into every executable.

The `bindgen` crate carries [upstream PR #3536](https://github.com/rust-lang/rust-bindgen/pull/3536),
which prevents recursive layout computation for uninstantiated template unions.

## Build

```sh
bazel build //:for_all_platforms
```

`.github/workflows/build_release.sh` builds with remote execution and writes six
maximum-compression `.tar.zst` archives plus `SHA256.txt`. Each archive contains
one executable named `bindgen` or `bindgen.exe`.

## Use

The executables do not include target headers or a sysroot. Pass the selected
C/C++ toolchain's Clang arguments and, when no separate Clang executable is
available, `--no-include-path-detection`.

## Release

```sh
./release.sh v0.0.4
```
