// swift-tools-version:5.9
// (Xcode15.0+)

import PackageDescription

// Prebuilt distribution of the LiveKit Swift SDK.
//
// `LiveKit` is shipped as a dynamic binary xcframework so it can be embedded
// once in the host app and shared with app extensions (e.g. the broadcast
// upload extension) via @rpath, instead of being statically linked into every
// binary. swift-protobuf, LKObjCHelpers and the Rust UniFFI static lib are
// absorbed into the framework; LiveKitWebRTC stays an external dynamic
// framework (linked via the shim below so it is embedded alongside LiveKit).
//
// The module format is NOT evolution-stable: build and consume with the same
// Xcode/Swift toolchain. Regenerate with scripts/build-xcframework.sh.
let package = Package(
    name: "LiveKit",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .macCatalyst(.v14),
        .tvOS(.v17),
    ],
    products: [
        .library(
            name: "LiveKit",
            targets: ["LiveKit", "LiveKitWebRTCShim"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/livekit/webrtc-xcframework.git", exact: "144.7559.03"),
    ],
    targets: [
        .binaryTarget(
            name: "LiveKit",
            url: "https://github.com/whopio/client-sdk-swift/releases/download/2.13.2-binary.1/LiveKit.xcframework.zip",
            checksum: "c2d84313cd0eea9cfa32fa3650c5586f11e6b3bead54fee3e69fa44531509852"
        ),
        .target(
            name: "LiveKitWebRTCShim",
            dependencies: [
                .product(name: "LiveKitWebRTC", package: "webrtc-xcframework"),
            ],
            path: "Sources/LiveKitWebRTCShim"
        ),
    ]
)
