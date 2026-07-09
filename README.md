# bindgen prebuilts

Hermetic `bindgen` 0.72.1 executables for Linux, macOS, and Windows on x86-64
and ARM64. Linux uses musl, Windows uses MSVC with the static CRT, and
`libclang` is linked into every executable.

## Build

```sh
bazel build //:for_all_platforms
```

`.github/workflows/build_release.sh` builds with remote execution and writes the
six release executables plus `SHA256.txt`.

## Use

The executables do not include target headers or a sysroot. Pass the selected
C/C++ toolchain's Clang arguments and, when no separate Clang executable is
available, `--no-include-path-detection`.

## Release

```sh
./release.sh v0.72.1-1
```
