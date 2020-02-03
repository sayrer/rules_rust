# Copyright 2018 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("@io_bazel_rules_rust//rust:private/rustc.bzl", "CrateInfo", "DepInfo", "get_lib_name")
load("@io_bazel_rules_rust//rust:private/utils.bzl", "find_toolchain")

def _rust_doc_test_impl(ctx):
    if CrateInfo not in ctx.attr.dep:
        fail("Expected rust library or binary.", "dep")

    crate = ctx.attr.dep[CrateInfo]
    rust_doc_test = ctx.outputs.executable

    toolchain = find_toolchain(ctx)

    dep_info = ctx.attr.dep[DepInfo]

    # Construct rustdoc test command, which will be written to a shell script
    # to be executed to run the test.
    ctx.actions.write(
        output = rust_doc_test,
        content = _build_rustdoc_test_script(toolchain, dep_info, crate),
        is_executable = True,
    )

    # The test script compiles the crate and runs it, so it needs both compile and runtime inputs.
    compile_inputs = depset(
        crate.srcs +
        [crate.output] +
        dep_info.transitive_libs +
        [toolchain.rust_doc] +
        [toolchain.rustc] +
        toolchain.crosstool_files,
        transitive = [
            toolchain.rustc_lib.files,
            toolchain.rust_lib.files,
        ],
    )

    runfiles = ctx.runfiles(
        files = compile_inputs.to_list(),
        collect_data = True,
    )
    return struct(runfiles = runfiles)

def dirname(path_str):
    return "/".join(path_str.split("/")[:-1])

def _build_rustdoc_test_script(toolchain, dep_info, crate):
    """ Constructs the rustdoc script used to test `crate`. """

    d = dep_info

    # nb. Paths must be constructed wrt runfiles, so we construct relative link flags for doctest.
    link_flags = []
    link_search_flags = []

    link_flags += ["--extern=" + crate.name + "=" + crate.output.short_path]
    link_flags += ["--extern=" + c.name + "=" + c.dep.output.short_path for c in d.direct_crates.to_list()]
    link_search_flags += ["-Ldependency={}".format(dirname(c.output.short_path)) for c in d.transitive_crates.to_list()]

    link_flags += ["-ldylib=" + get_lib_name(lib) for lib in d.transitive_dylibs.to_list()]
    link_search_flags += ["-Lnative={}".format(dirname(lib.short_path)) for lib in d.transitive_dylibs.to_list()]
    link_flags += ["-lstatic=" + get_lib_name(lib) for lib in d.transitive_staticlibs.to_list()]
    link_search_flags += ["-Lnative={}".format(dirname(lib.short_path)) for lib in d.transitive_staticlibs.to_list()]

    edition_flags = ["--edition={}".format(crate.edition)] if crate.edition != "2015" else []

    flags = link_search_flags + link_flags + edition_flags

    return """\
#!/usr/bin/env bash

set -e;

{rust_doc} --test \\
    {crate_root} \\
    --crate-name={crate_name} \\
    {flags}
""".format(
        rust_doc = toolchain.rust_doc.path,
        crate_root = crate.root.path,
        crate_name = crate.name,
        # TODO: Should be possible to do this with ctx.actions.Args, but can't seem to get them as a str and into the template.
        flags = " \\\n    ".join(flags),
    )

rust_doc_test = rule(
    _rust_doc_test_impl,
    attrs = {
        "dep": attr.label(
            doc = """
The label of the target to run documentation tests for.

`rust_doc_test` can run documentation tests for the source files of
`rust_library` or `rust_binary` targets.
""",
            mandatory = True,
            providers = [CrateInfo],
        ),
    },
    executable = True,
    test = True,
    toolchains = ["@io_bazel_rules_rust//rust:toolchain"],
    doc = """
Runs Rust documentation tests.

Example:

Suppose you have the following directory structure for a Rust library crate:

```
[workspace]/
  WORKSPACE
  hello_lib/
      BUILD
      src/
          lib.rs
```

To run [documentation tests][doc-test] for the `hello_lib` crate, define a
`rust_doc_test` target that depends on the `hello_lib` `rust_library` target:

[doc-test]: https://doc.rust-lang.org/book/documentation.html#documentation-as-tests

```python
package(default_visibility = ["//visibility:public"])

load("@io_bazel_rules_rust//rust:rust.bzl", "rust_library", "rust_doc_test")

rust_library(
    name = "hello_lib",
    srcs = ["src/lib.rs"],
)

rust_doc_test(
    name = "hello_lib_doc_test",
    dep = ":hello_lib",
)
```

Running `bazel test //hello_lib:hello_lib_doc_test` will run all documentation tests for the `hello_lib` library crate.
""",
)
