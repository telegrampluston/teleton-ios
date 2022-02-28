load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ForkNetwork",
    module_name = "ForkNetwork",
    srcs = glob([
    "Sources/**/*.swift",
    ]),
  deps = [
      "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
      "//submodules/EasyDi:EasyDi",
      "//submodules/ForkTelegramInterface:ForkTelegramInterface",
  ],
    visibility = [
        "//visibility:public",
    ],
)
