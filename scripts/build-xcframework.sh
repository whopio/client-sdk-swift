#!/bin/bash
#
# Builds LiveKit.xcframework — a dynamic binary distribution of the LiveKit
# Swift SDK — for ios-arm64 (device) and ios-arm64 (simulator).
#
# Why the unusual approach:
#   * Xcode 26.x statically MERGES a single-consumer `.dynamic` SwiftPM library
#     product into its consumer, so building the package never emits a
#     standalone framework. We build a throwaway wrapper app that links the
#     LiveKit product (which yields per-target merged .o files) and relink those
#     ourselves into a real dynamic framework.
#   * We build via the wrapper app rather than the package scheme directly
#     because the auto-generated package scheme instruments every object for
#     code coverage (undefined __llvm_profile_runtime at link time).
#   * A non-evolution .swiftmodule leaks LiveKit's internal module deps
#     (LKObjCHelpers/SwiftProtobuf/LiveKitUniFFI) to consumers, so we build with
#     BUILD_LIBRARY_FOR_DISTRIBUTION=YES and ship the .swiftinterface. Those deps
#     are `internal import`ed in LiveKit's sources so they stay hidden + absorbed.
#
# Result: LiveKit.framework statically absorbs SwiftProtobuf, LKObjCHelpers and
# the Rust liblivekit_uniffi.a; it links LiveKitWebRTC.framework dynamically via
# @rpath (NOT absorbed). Consumers must also embed LiveKitWebRTC.framework — the
# package's LiveKitWebRTCShim target expresses that so SwiftPM does it for them.
#
# Build and consume with the SAME Xcode/Swift toolchain (module format tracks the
# compiler; the monorepo pins it via .xcode-version). Requires xcodegen.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${BUILD_DIR:-$ROOT/.xcframework-build}"
SPM_CACHE="$BUILD/spm-cache"
WRAP="$BUILD/wrapper"
CLANG="$(xcrun -f clang)"
STRIP="$(xcrun -f strip)"
XCODEGEN="${XCODEGEN:-xcodegen}"; command -v "$XCODEGEN" >/dev/null || XCODEGEN="mint run xcodegen"

rm -rf "$BUILD/asm" "$BUILD/LiveKit.xcframework" "$BUILD/LiveKit.xcframework.zip" "$WRAP" "$BUILD/src"
mkdir -p "$BUILD/asm" "$WRAP/Sources"

# The branch's Package.swift is the binary distribution manifest. To rebuild the
# framework from source we materialize a source checkout that uses the source
# manifest (Package.source.swift) instead, and point the wrapper at it.
SRC="$BUILD/src"
rsync -a --exclude .git --exclude .xcframework-build "$ROOT/" "$SRC/"
cp "$SRC/Package.source.swift" "$SRC/Package.swift"
rm -f "$SRC"/Package@swift-*.swift  # ensure the source manifest wins for every toolchain

cat > "$WRAP/project.yml" <<YML
name: LiveKitWrap
options: {bundleIdPrefix: io.livekit.wrap, deploymentTarget: {iOS: "15.0"}}
settings: {base: {CODE_SIGNING_ALLOWED: "NO", CODE_SIGNING_REQUIRED: "NO", CODE_SIGN_IDENTITY: ""}}
packages: {LiveKit: {path: "$SRC"}}
targets:
  LiveKitWrap:
    type: application
    platform: iOS
    sources: [Sources]
    info:
      path: Sources/Info.plist
      properties: {CFBundleName: LiveKitWrap}
    dependencies: [{package: LiveKit, product: LiveKit}]
YML
printf 'import LiveKit\n_ = Room.self\n' > "$WRAP/Sources/main.swift"
( cd "$WRAP" && $XCODEGEN generate >/dev/null )

build_slice() { # <destination> <ddtag> <extra xcodebuild args...>
  local dest="$1" tag="$2"; shift 2
  ( cd "$WRAP" && xcodebuild build \
      -project LiveKitWrap.xcodeproj -scheme LiveKitWrap -configuration Release -destination "$dest" \
      -clonedSourcePackagesDirPath "$SPM_CACHE" -derivedDataPath "$BUILD/$tag" \
      CODE_SIGNING_ALLOWED=NO SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES ONLY_ACTIVE_ARCH=NO "$@" )
}

# <ddtag> <productsubdir> <sdk> <clang-target> <swift-triple> <platform> <swiftlibdir>
make_framework() {
  local tag="$1" sub="$2" sdk="$3" triple="$4" swifttriple="$5" platform="$6" swiftlib="$7"
  local prod="$BUILD/$tag/Build/Products/$sub"
  local fw="$BUILD/asm/$tag/LiveKit.framework"
  local sdkpath; sdkpath="$(xcrun --sdk "$sdk" --show-sdk-path)"
  local xtlib; xtlib="$(dirname "$CLANG")/../lib/swift/$swiftlib"

  mkdir -p "$fw/Modules/LiveKit.swiftmodule"
  "$CLANG" -dynamiclib -target "$triple" -isysroot "$sdkpath" \
    -install_name "@rpath/LiveKit.framework/LiveKit" \
    -L"$prod" -F"$prod" -L"$xtlib" -L/usr/lib/swift -fobjc-link-runtime \
    -Xlinker -rpath -Xlinker /usr/lib/swift \
    -Xlinker -rpath -Xlinker "@loader_path/.." \
    -Xlinker -rpath -Xlinker "@loader_path/Frameworks" \
    -Xlinker -rpath -Xlinker "@executable_path/Frameworks" \
    -Wl,-no_warn_duplicate_libraries \
    "$prod/LiveKit.o" "$prod/LKObjCHelpers.o" "$prod/LiveKitUniFFI.o" "$prod/SwiftProtobuf.o" \
    -llivekit_uniffi -framework LiveKitWebRTC \
    -o "$fw/LiveKit"
  "$STRIP" -x "$fw/LiveKit"

  local m="$prod/LiveKit.swiftmodule"
  cp "$m/$swifttriple.swiftinterface"         "$fw/Modules/LiveKit.swiftmodule/"
  cp "$m/$swifttriple.private.swiftinterface" "$fw/Modules/LiveKit.swiftmodule/" 2>/dev/null || true
  cp "$m/$swifttriple.swiftmodule"            "$fw/Modules/LiveKit.swiftmodule/"
  cp "$m/$swifttriple.swiftdoc"               "$fw/Modules/LiveKit.swiftmodule/"
  cp "$m/$swifttriple.abi.json"               "$fw/Modules/LiveKit.swiftmodule/" 2>/dev/null || true
  [ -d "$prod/LiveKit_LiveKit.bundle" ] && cp -a "$prod/LiveKit_LiveKit.bundle" "$fw/"

  cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>LiveKit</string>
	<key>CFBundleIdentifier</key><string>io.livekit.LiveKit</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>LiveKit</string>
	<key>CFBundlePackageType</key><string>FMWK</string>
	<key>CFBundleShortVersionString</key><string>2.13.1</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>MinimumOSVersion</key><string>15.0</string>
	<key>CFBundleSupportedPlatforms</key><array><string>$platform</string></array>
</dict></plist>
PLIST
}

build_slice "generic/platform=iOS" ios
build_slice "generic/platform=iOS Simulator" sim ARCHS=arm64 EXCLUDED_ARCHS=x86_64

make_framework ios Release-iphoneos        iphoneos        arm64-apple-ios15.0            arm64-apple-ios           iPhoneOS        iphoneos
make_framework sim Release-iphonesimulator iphonesimulator arm64-apple-ios15.0-simulator arm64-apple-ios-simulator iPhoneSimulator iphonesimulator

OUT="$BUILD/LiveKit.xcframework"
mkdir -p "$OUT/ios-arm64" "$OUT/ios-arm64-simulator"
cp -a "$BUILD/asm/ios/LiveKit.framework" "$OUT/ios-arm64/LiveKit.framework"
cp -a "$BUILD/asm/sim/LiveKit.framework" "$OUT/ios-arm64-simulator/LiveKit.framework"
cat > "$OUT/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>AvailableLibraries</key><array>
		<dict>
			<key>BinaryPath</key><string>LiveKit.framework/LiveKit</string>
			<key>LibraryIdentifier</key><string>ios-arm64</string>
			<key>LibraryPath</key><string>LiveKit.framework</string>
			<key>SupportedArchitectures</key><array><string>arm64</string></array>
			<key>SupportedPlatform</key><string>ios</string>
		</dict>
		<dict>
			<key>BinaryPath</key><string>LiveKit.framework/LiveKit</string>
			<key>LibraryIdentifier</key><string>ios-arm64-simulator</string>
			<key>LibraryPath</key><string>LiveKit.framework</string>
			<key>SupportedArchitectures</key><array><string>arm64</string></array>
			<key>SupportedPlatform</key><string>ios</string>
			<key>SupportedPlatformVariant</key><string>simulator</string>
		</dict>
	</array>
	<key>CFBundlePackageType</key><string>XFWK</string>
	<key>XCFrameworkFormatVersion</key><string>1.0</string>
</dict></plist>
PLIST

ditto -c -k --sequesterRsrc --keepParent "$OUT" "$BUILD/LiveKit.xcframework.zip"
echo "xcframework: $OUT"
echo "zip:         $BUILD/LiveKit.xcframework.zip ($(stat -f%z "$BUILD/LiveKit.xcframework.zip") bytes)"
echo "checksum:    $(cd "$ROOT" && swift package compute-checksum "$BUILD/LiveKit.xcframework.zip")"
