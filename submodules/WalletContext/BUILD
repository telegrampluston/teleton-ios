load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "WalletContext",
    module_name = "WalletContext",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    deps = [
        "//submodules/WalletCore:WalletCore",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/Display:Display",
    ],
    visibility = [
        "//visibility:public",
    ],
)
