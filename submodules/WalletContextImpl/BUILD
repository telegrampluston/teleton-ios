load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "WalletContextImpl",
    module_name = "WalletContextImpl",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    deps = [
        "//submodules/WalletCore:WalletCore",
        "//submodules/ForkWalletCore:ForkWalletCore",
        "//submodules/AccountContext:AccountContext",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/DeviceAccess:DeviceAccess",
        "//submodules/Display:Display",
        "//submodules/WalletContext:WalletContext",
        "//submodules/BuildConfig:BuildConfig",
        "//submodules/AppBundle:AppBundle",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/ShareController:ShareController",
        "//submodules/TelegramCore:TelegramCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
