import AppKit
if CommandLine.arguments.contains("--virtual-display-helper") { exit(ADVirtualScreen.runHelper(CommandLine.arguments)) }
setbuf(stdout, nil)
print("DIAGNOSTIC start")
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
#if DIAGNOSTIC_SCENE
if CommandLine.arguments.contains("scene") { DiagnosticScene.show(); print("DIAGNOSTIC scene ready") }
#endif
application.finishLaunching()
func pumpApplication(until deadline: Date) {
    if let event = application.nextEvent(matching: .any, until: deadline, inMode: .default, dequeue: true) {
        application.sendEvent(event)
    }
    application.updateWindows()
}
func option(_ prefix: String, _ fallback: Int) -> Int { Int(CommandLine.arguments.first { $0.hasPrefix(prefix) }?.dropFirst(prefix.count) ?? "") ?? fallback }
let engine = SenderEngine(); engine.screenPermission = { true }
let cursorRectLock = NSLock()
var cursorRect = CGDisplayBounds(CGMainDisplayID())
let inputProbe = CommandLine.arguments.contains("input-probe")
var probePosition = CGPoint(x: 0.5, y: 0.5)
// Inspect the real input path without ever posting to the user's desktop.
engine.pointer.post = { event in
    guard inputProbe, event.type == .mouseMoved else { return }
    let target = DisplayGeometry.shared.bounds(CGMainDisplayID())
    cursorRectLock.lock()
    probePosition = CGPoint(x: (event.location.x-target.minX)/max(1,target.width-1), y: (event.location.y-target.minY)/max(1,target.height-1))
    cursorRectLock.unlock()
}
engine.keyboard.post = { _ in }
if inputProbe && !CommandLine.arguments.contains("permission-probe") {
    engine.pointer.trusted = { true }; engine.desktopPermission = { true }
}
if CommandLine.arguments.contains("permission-probe") { print("DIAGNOSTIC actual accessibility permission", AXIsProcessTrusted()) }
let origin = monotonicNS()
engine.cursorLocation = {
    cursorRectLock.lock(); let rect = cursorRect, probe = probePosition; cursorRectLock.unlock()
    if inputProbe { return CGPoint(x: rect.minX+rect.width*probe.x, y: rect.minY+rect.height*probe.y) }
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
let settingsTrial = CommandLine.arguments.contains("settings")
let savedLayout = UserDefaults.standard.object(forKey: "PrisonDisplay.layout")
let schedule: [StreamOptions] = [
    StreamOptions(extend: false, width: 1280, height: 720, fps: 30, bitrate: 6_000_000),
    StreamOptions(extend: false, width: 1920, height: 1080, fps: 60, bitrate: 12_000_000),
    StreamOptions(extend: false, width: 1920, height: 1080, fps: 60, bitrate: 20_000_000),
    StreamOptions(extend: false, width: 1920, height: 1080, fps: 60, bitrate: 40_000_000),
    StreamOptions(extend: false, width: 2560, height: 1440, fps: 30, bitrate: 20_000_000, nativeCursor: true),
    StreamOptions(extend: true, width: 1280, height: 720, fps: 30, bitrate: 6_000_000),
    StreamOptions(extend: true, width: 1920, height: 1080, fps: 60, bitrate: 20_000_000),
    StreamOptions(extend: true, width: 2560, height: 1440, fps: 30, bitrate: 40_000_000)
]
var firstConnection: Date?
var step = -1
var connectedAt: Date?
var finished = false
var trialCompleted = false
var trialFailure: String?
var roundTrips: [Double] = []
engine.onFrameRoundTrip = { roundTrips.append($0) }
engine.onLink = { link in
    guard let link = link else { return }
    try! link.url.absoluteString.write(toFile: path, atomically: true, encoding: .utf8)
    try! FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
}
engine.onStatus = { status in
    print("STATUS", status)
    if status.contains("Duplicando") || status.contains("Escritorio extendido activo") { connectedAt = Date() }
    if status.contains("desconect") || status.contains("saturando el sistema de color") {
        trialFailure = status; finished = true
    }
}
engine.onMetrics = { print("METRIC", $0) }
if settingsTrial || CommandLine.arguments.contains("extend") {
    engine.onSessionActive = {
        let bounds = CGDisplayBounds(engine.pointer.displayID)
        cursorRectLock.lock(); cursorRect = bounds; cursorRectLock.unlock()
        DispatchQueue.main.async {
            if firstConnection == nil { firstConnection = Date() }
            let displayID = engine.pointer.displayID
            if let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID }) {
                // A window moved off a retired monitor can have suspended layer
                // animations. Recreate only our fixture on the current monitor.
                DiagnosticScene.show(frame: screen.visibleFrame)
            } else {
                // AppKit's screen list can lag a just-created virtual monitor.
                // Place our own fixture using the live CoreGraphics geometry.
                let primary = CGDisplayBounds(CGMainDisplayID())
                DiagnosticScene.show(frame: NSRect(x: bounds.minX, y: primary.maxY-bounds.maxY, width: bounds.width, height: bounds.height))
            }
            print("SCENE target", displayID, "CG", bounds, "NS", DiagnosticScene.window?.frame as Any)
        }
    }
}
print("DIAGNOSTIC before listener")
try engine.start(key: newPairingKey(), options: StreamOptions(extend: CommandLine.arguments.contains("extend"), width: option("w=", 1920), height: option("h=", 1080), fps: option("fps=", 60), bitrate: bitrate, nativeCursor: CommandLine.arguments.contains("native-cursor")))
let deadline = Date().addingTimeInterval(settingsTrial ? 180 : max(60, duration+20))
while !finished && Date() < deadline {
    pumpApplication(until: Date().addingTimeInterval(0.01))
    if settingsTrial, let start = firstConnection {
        let elapsed = Date().timeIntervalSince(start)
        let next = Int(elapsed / 8)
        if next >= schedule.count { trialCompleted = true; break }
        if next > step {
            step = next;let options = schedule[step]
            print("SETTINGS STEP", step, "extend", options.extend, "size", options.width, options.height, "fps", options.fps, "quality", options.bitrate, "native", options.nativeCursor)
            engine.update(options: options)
        }
    } else if let start = connectedAt, Date().timeIntervalSince(start) > duration { trialCompleted = true; break }
}
engine.stop()
#if DIAGNOSTIC_SCENE
DiagnosticScene.window?.close()
DiagnosticScene.refresh?.invalidate()
print("SCENE refreshTicks=\(DiagnosticScene.ticks)")
#endif
let usedExtension = settingsTrial || CommandLine.arguments.contains("extend")
let stopDeadline = Date().addingTimeInterval(usedExtension ? 3 : 0.2)
while Date() < stopDeadline { pumpApplication(until: Date().addingTimeInterval(0.01)) }
if usedExtension {
    if let value = savedLayout { UserDefaults.standard.set(value, forKey: "PrisonDisplay.layout") }
    else { UserDefaults.standard.removeObject(forKey: "PrisonDisplay.layout") }
    UserDefaults.standard.synchronize()
}
roundTrips.sort()
print("FRAME RTT samples=\(roundTrips.count) medianMS=\(roundTrips.isEmpty ? 0 : roundTrips[roundTrips.count/2]) p95MS=\(roundTrips.isEmpty ? 0 : roundTrips[min(roundTrips.count-1,Int(Double(roundTrips.count)*0.95))]) maxMS=\(roundTrips.last ?? 0)")

print("DONE", AppVersion.current)
print("TRIAL completed=\(trialCompleted) failure=\(trialFailure ?? "none")")
exit(trialCompleted && trialFailure == nil ? 0 : 1)
