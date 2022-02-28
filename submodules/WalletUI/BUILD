load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

filegroup(
    name = "WalletUIResources",
    srcs = glob([
        "Resources/**/*",
    ], exclude = ["Resources/**/.*"]),
    visibility = ["//visibility:public"],
)

filegroup(
    name = "WalletUIAssets",
    srcs = glob(["WalletImages.xcassets/**"]),
    visibility = ["//visibility:public"],
)

swift_library(
    name = "WalletUI",
    module_name = "WalletUI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/OverlayStatusController:OverlayStatusController",
        "//submodules/AppBundle:AppBundle",
        "//submodules/SolidRoundedButtonNode:SolidRoundedButtonNode",
        "//submodules/AlertUI:AlertUI",
        "//submodules/Camera:Camera",
        "//submodules/QrCode:QrCode",
        "//submodules/MergeLists:MergeLists",
        "//submodules/GlassButtonNode:GlassButtonNode",
        "//submodules/UrlEscaping:UrlEscaping",
        "//submodules/LocalAuth:LocalAuth",
        "//submodules/WalletUrl:WalletUrl",
        "//submodules/WalletCore:WalletCore",
        "//submodules/Markdown:Markdown",
        "//submodules/AnimatedStickerNode:AnimatedStickerNode",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/WalletContext:WalletContext",
    ],
    visibility = [
        "//visibility:public",
    ],
)
