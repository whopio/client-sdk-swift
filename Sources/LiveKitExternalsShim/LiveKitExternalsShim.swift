// Forces SwiftPM to embed the external dynamic frameworks that the prebuilt
// LiveKit.framework loads via @rpath (LiveKitWebRTC + RustLiveKitUniFFI). A
// binaryTarget carries no dependency info, so this target's manifest
// dependencies re-express those links. Nothing needs to import this module.
@_exported import LiveKitWebRTC
