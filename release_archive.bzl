load("@tar.bzl//tar:tar.bzl", "tar")

def _release_mtree_impl(ctx):
    content = "%s uid=0 gid=0 time=1672560000 mode=0755 type=file content=$(location %s)\n" % (
        ctx.attr.binary_name,
        str(ctx.attr.binary.label),
    )
    content = ctx.expand_location(content, targets = [ctx.attr.binary])

    output = ctx.actions.declare_file(ctx.attr.name)
    ctx.actions.write(output = output, content = content)

    return [DefaultInfo(files = depset([output]))]

_release_mtree = rule(
    implementation = _release_mtree_impl,
    attrs = {
        "binary": attr.label(allow_single_file = True, mandatory = True),
        "binary_name": attr.string(mandatory = True),
    },
)

def release_archive(name, binary, binary_name):
    mtree_name = name + "_mtree"
    _release_mtree(
        name = mtree_name,
        binary = binary,
        binary_name = binary_name,
    )
    tar(
        name = name,
        srcs = [binary],
        args = [
            "--options",
            "zstd:compression-level=22",
        ],
        compress = "zstd",
        mtree = mtree_name,
    )
