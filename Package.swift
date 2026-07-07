// swift-tools-version:5.9
// (Xcode15.0+)

import PackageDescription

// Prebuilt distribution of the LiveKit Swift SDK.
//
// `LiveKit` is shipped as a dynamic binary xcframework so it can be embedded
// once in the host app and shared with app extensions (e.g. the broadcast
// upload extension) via @rpath, instead of being statically linked into every
// binary. swift-protobuf, LKObjCHelpers and the uniffi Swift bindings are
// absorbed into the framework; LiveKitWebRTC and RustLiveKitUniFFI stay external
// dynamic frameworks (linked via the shim below so they are embedded alongside
// LiveKit). uniffi 0.0.6 ships the Rust lib as a ~0.9MB dynamic framework,
// avoiding the ~11.5MB bindgen bloat the 0.0.5 static archive pulled in.
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
            targets: ["LiveKit", "LiveKitExternalsShim"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/livekit/webrtc-xcframework.git", exact: "144.7559.03"),
    ],
    targets: [
        .binaryTarget(
            name: "LiveKit",
            url: "https://github.com/whopio/client-sdk-swift/releases/download/2.13.2-binary.4/LiveKit.xcframework.zip",
            checksum: "0e1398685b1b805697659877217e064e9b42262987ac8c716c8c16d20d2ae7cd"
        ),
        .binaryTarget(
            name: "RustLiveKitUniFFI",
            url: "https://github.com/livekit/livekit-uniffi-xcframework/releases/download/0.0.6/RustLiveKitUniFFI.xcframework.zip",
            checksum: "0d3f2ce159a224c728f8b131068d53bbf9b13d968cda0edc68a6a2290f2651ed"
        ),
        .target(
            name: "LiveKitExternalsShim",
            dependencies: [
                .product(name: "LiveKitWebRTC", package: "webrtc-xcframework"),
                "RustLiveKitUniFFI",
            ],
            path: "Sources/LiveKitExternalsShim"
        ),
    ]
)
