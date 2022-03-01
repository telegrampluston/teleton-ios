load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:apple.bzl","apple_dynamic_framework_import")

filegroup(
    name = "ForkWalletCoreResources",
    srcs = glob([
        "Resources/**/*",
    ], exclude = ["Resources/**/.*"]),
    visibility = ["//visibility:public"],
)

swift_library(
    name = "ForkWalletCore",
    module_name = "ForkWalletCore",
    srcs = glob([
	"Sources/**/*.swift",
    ]),
    deps = [
        "//submodules/AccountContext:AccountContext",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/ForkNetwork:ForkNetwork",
        "//submodules/ForkTelegramInterface:ForkTelegramInterface",
        "//submodules/EasyDi:EasyDi",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/Display:Display",
        "//submodules/Postbox:Postbox",
        "//submodules/OverlayStatusController:OverlayStatusController",
    ],
    visibility = [
        "//visibility:public",
    ],
)
