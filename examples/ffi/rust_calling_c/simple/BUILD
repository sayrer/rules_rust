load("@io_bazel_rules_rust//rust:rust.bzl", "rust_binary", "rust_doc", "rust_library", "rust_test")
load("@io_bazel_rules_rust//bindgen:bindgen.bzl", "rust_bindgen_library")

cc_library(
    name = "simple",
    srcs = ["simple.h"],
)

rust_bindgen_library(
    name = "simple_bindgen",
    bindgen_flags = [
        "--whitelist-var=SIMPLE_.*",
    ],
    cc_lib = ":simple",
    header = "simple.h",
)

rust_binary(
    name = "simple_example",
    srcs = ["main.rs"],
    deps = [":simple_bindgen"],
)

rust_test(
    name = "simple_test",
    crate = ":simple_example",
)
