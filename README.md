# bindgen prebuilts

This repository builds and publishes self-contained `bindgen` executables for
the six OS/CPU combinations used by `rules_rs`. The pinned upstream version is
`bindgen-cli` 0.72.1.

The build compiles `libclang` into `bindgen`, enables ThinLTO for every target,
and fully strips every release executable. The patched `rules_rust` final link
runs hermetic `rust-objcopy --strip-all` for ELF and Mach-O. The MSVC links
use `lld-link /DEBUG:NONE` and produce no COFF symbol table, CodeView record, or
PDB dependency. Linux
uses musl and has no ELF interpreter or dynamic imports. Darwin executables
may import only Apple libraries under `/System/Library` and `/usr/lib`, including Apple's
`/usr/lib/libc++.1.dylib`. Windows executables use Rust's `windows-msvc`
targets. Rust uses `-Ctarget-feature=+crt-static`, and LLVM/libclang use
`static_link_msvcrt` (`/MT`).

The patched hermetic LLVM toolchain builds its stage-one compiler from the
pinned LLVM 22.1.8 source so the MSVC ThinLTO fixes apply to the final links.
Remote execution uses the pinned amd64 manifest of Ubuntu 22.04.

The executable intentionally does not contain a target sysroot or target
headers. A consumer must pass the selected C/C++ toolchain's declared Clang
arguments. A consumer that does not provide a separate Clang executable must
also pass `--no-include-path-detection` so `bindgen` does not search the host.

## Build

Build every release executable:

```sh
bazel build //:for_all_platforms
```

To use BuildBuddy remote execution, add `--config=remote` and a BuildBuddy API
key header. `.github/workflows/build_release.sh` builds the same target, copies
the six raw executables, and writes `SHA256.txt`.

Release tags use the upstream version plus a packaging revision, for example
`v0.72.1-1`.
