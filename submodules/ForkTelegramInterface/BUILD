load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ForkTelegramInterface",
    module_name = "ForkTelegramInterface",
    srcs = glob([
    "Sources/**/*.swift",
    ]),
  deps = [
      "//submodules/AccountContext:AccountContext",
      "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
      "//submodules/EasyDi:EasyDi",
  ],
    visibility = [
        "//visibility:public",
    ],
)
