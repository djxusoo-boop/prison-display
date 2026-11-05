import AppKit
#if DIAGNOSTIC_SCENE
if CommandLine.arguments.contains("scene") { DiagnosticScene.show() }
#endif
let engine = SenderEngine(); engine.screenPermission = { true }
let rect = CGDisplayBounds(CGMainDisplayID())
let origin = monotonicNS()
engine.cursorLocation = {
    let t = Double(monotonicNS() - origin) / 1e9
    return CGPoint(x: rect.minX + rect.width*(0.5 + sin(t*2)*0.4), y: rect.minY + rect.height*(0.5 + cos(t*2)*0.4))
}
if CommandLine.arguments.contains("inline-cursor") { engine.dedicatedCursorEnabled = false }
if CommandLine.arguments.contains("dedicated-cursor") { engine.dedicatedCursorEnabled = true }
if CommandLine.arguments.contains("three-images") { engine.videoFlightLimit = 3 }
if CommandLine.arguments.contains("one-image") { engine.videoFlightLimit = 1 }
if CommandLine.arguments.contains("two-images") { engine.videoFlightLimit = 2 }
let path = CommandLine.arguments[1]
let bitrate = Int(CommandLine.arguments[2])!
let duration = Double(CommandLine.arguments[3])!
var connectedAt: Date?
var finished = false
var roundTrips: [Double] = []
engine.onFrameRoundTrip = { roundTrips.append($0) }
engine.onLink = { link in
    guard let link = link else { return }
    try! link.url.absoluteString.write(toFile: path, atomically: true, encoding: .utf8)
    try! FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
}
engine.onStatus = { status in
    print("STATUS", status)
    if status.contains("Duplicando") { connectedAt = Date() }
    if status.contains("desconect") { finished = true }
}
engine.onMetrics = { print("METRIC", $0) }
try engine.start(key: newPairingKey(), options: StreamOptions(extend: false, width: 1920, height: 1080, fps: 60, bitrate: bitrate))
let deadline = Date().addingTimeInterval(60)
while !finished && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    if let start = connectedAt, Date().timeIntervalSince(start) > duration { break }
}
engine.stop()
#if DIAGNOSTIC_SCENE
DiagnosticScene.window?.close()
#endif
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
roundTrips.sort()
print("FRAME RTT samples=\(roundTrips.count) medianMS=\(roundTrips.isEmpty ? 0 : roundTrips[roundTrips.count/2]) p95MS=\(roundTrips.isEmpty ? 0 : roundTrips[min(roundTrips.count-1,Int(Double(roundTrips.count)*0.95))]) maxMS=\(roundTrips.last ?? 0)")
print("DONE", AppVersion.current)
