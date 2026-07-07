// Links LiveKitWebRTC so SwiftPM embeds LiveKitWebRTC.framework into any app
// that consumes the prebuilt LiveKit binary. The prebuilt LiveKit.framework
// references WebRTC via @rpath/LiveKitWebRTC.framework, but a binaryTarget
// carries no dependency info, so this shim re-expresses that link. Nothing
// needs to import this module.
@_exported import LiveKitWebRTC
