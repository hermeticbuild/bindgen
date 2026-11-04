#include <stddef.h>
#include <stdint.h>

#if defined(__x86_64__)
#include <immintrin.h>
#elif defined(__aarch64__)
#include <arm_neon.h>
#endif

enum {
    parser_major = __clang_major__,
    parser_minor = __clang_minor__,
    parser_patch = __clang_patchlevel__,
};

struct bindgen_probe {
    uint64_t value;
    size_t size;
};
