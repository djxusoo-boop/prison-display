import AppKit
#if !LEGACY
import Network
#endif
import CoreImage
import ImageIO

if let path = CommandLine.arguments.first(where: { $0.hasPrefix("log=") }).map({ String($0.dropFirst(4)) }) {
    umask(0o077); _ = freopen(path,"w",stdout); _ = freopen(path+".errors","w",stderr)
}
setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let view = VideoView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
window.title = "PRISON DISPLAY · Prueba temporal v\(AppVersion.current)"
window.contentView = view; window.center(); window.orderFrontRegardless()
let engine = ReceiverEngine()
let lock = NSLock()
var frames = 0, shown = 0
var lastDimensions = ""
var started: UInt64?
var cursorTimes: [UInt64] = []
var frameTimes: [UInt64] = []
var finished = false, connected = false, dedicated = false
var latestMetrics = ""
let inputProbe = CommandLine.arguments.contains("input-probe")
var probeReady = false, probeIndex = 0
var probeSent: [Int: UInt64] = [:], probeRTT: [Double] = []
let probeToken: UInt64 = 9123
var probeHeartbeat: UInt64 = 0
var probeTimer: DispatchSourceTimer?
var probeLastBegin: UInt64 = 0
func startProbeIfReady() {
    guard inputProbe else { return }
    lock.lock(); let ready = dedicated && frames > 0; lock.unlock()
    if ready { engine.sendDesktopControl(DesktopControlMessage(action: .begin, token: probeToken)) }
}
if inputProbe {
    engine.onSessionActive = { startProbeIfReady() }
    engine.onDesktopControl = { message in
        lock.lock(); probeReady = message.action == .accepted && message.token == probeToken; lock.unlock()
    }
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "PrisonDisplay.simulated-input", qos: .userInteractive))
    timer.schedule(deadline: .now(), repeating: .microseconds(8333))
    timer.setEventHandler {
        lock.lock()
        guard probeReady else {
            let now = monotonicNS(), canBegin = dedicated && frames > 0 && now-probeLastBegin >= 250_000_000
            if canBegin { probeLastBegin = now }; lock.unlock()
            if canBegin { engine.sendDesktopControl(DesktopControlMessage(action: .begin, token: probeToken)) }
            return
        }
        let now = monotonicNS(); probeIndex += 1; let index = probeIndex
        probeSent[index] = now
        let heartbeat = now-probeHeartbeat > 500_000_000
        if heartbeat { probeHeartbeat = now }
        lock.unlock()
        if heartbeat { engine.sendDesktopControl(DesktopControlMessage(action: .heartbeat, token: probeToken)) }
        engine.sendPointer(PointerMessage(action: .move, x: 0.1+Double(index)/100000, y: 0.5))
    }
    probeTimer = timer; timer.resume()
}
let imagePresenter = LatestVideoPresenter { pixel in
    let accepted = try view.present(pixel); lock.lock(); if accepted { shown += 1 }; lock.unlock(); return accepted
}
let cursorPresenter = LatestCursorPresenter { x,y,visible,_ in view.remoteCursor(x: x,y: y,visible: visible) }
engine.onPixel = { pixel, done in
    lock.lock(); frames += 1; let frameNumber = frames; let arrival = monotonicNS(); frameTimes.append(arrival); if started == nil { started = arrival }; lock.unlock()
    if [10,60].contains(frameNumber), CommandLine.arguments.contains("snapshot") {
        let ci = CIImage(cvPixelBuffer: pixel)
        if let image = CIContext().createCGImage(ci, from: ci.extent),
           let file = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "/private/tmp/PRISON-DISPLAY-investigate/received-scene-\(AppVersion.current)-\(frameNumber).png") as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(file, image, nil); print("SNAPSHOT saved=\(CGImageDestinationFinalize(file))")
        }
    }
    let dimensions = "\(CVPixelBufferGetWidth(pixel))x\(CVPixelBufferGetHeight(pixel))"
    if lastDimensions != dimensions { lastDimensions = dimensions; print("FORMAT", dimensions) }
    imagePresenter.submit(pixel, completion: done)
}
engine.onCursor = { x,y,visible,permitted in
    lock.lock(); let now = monotonicNS(); cursorTimes.append(now)
    if inputProbe, let sent = probeSent.removeValue(forKey: Int(((x-0.1)*100000).rounded())) { probeRTT.append(Double(now-sent)/1e6) }
    lock.unlock()
    cursorPresenter.submit(x: x,y: y,visible: visible,permitted: permitted)
}
engine.onCursorMode = { value in print("CURSOR MODE", value); DispatchQueue.main.async { view.cursorInVideo = value } }
engine.onMetrics = { value in lock.lock(); latestMetrics = value; lock.unlock() }
engine.onStatus = { print("STATUS",$0) }
engine.onConnection = { value in DispatchQueue.main.async {
    if value { connected = true } else if connected { finished = true }
} }
#if REAL_ROUTE_DIAGNOSTIC
engine.onNetworkReady = { path in print("ROUTE",path?.remoteEndpoint as Any,path?.availableInterfaces.map { $0.name } as Any) }
engine.onInteractiveReady = { lock.lock(); dedicated = true; lock.unlock(); print("CURSOR dedicated TLS ready"); startProbeIfReady() }
#endif
let text = try String(contentsOfFile: CommandLine.arguments[1]).trimmingCharacters(in: .whitespacesAndNewlines)
let link = try ConnectionLink(URL(string: text)!)
let router = CommandLine.arguments.contains("router")
try engine.connect(endpoint: router ? link.hostEndpoint : link.endpoint, key: link.key, fallback: router ? nil : link.hostEndpoint, previouslyApproved: true)
app.finishLaunching()
// Include setup/first-image time; the sender owns the measured stream duration.
let requestedDuration = CommandLine.arguments.first { $0.hasPrefix("duration=") }.flatMap { Double($0.dropFirst("duration=".count)) } ?? 12
let deadline = Date().addingTimeInterval(max(180, requestedDuration + 30))
while !finished && Date() < deadline {
    if let event = app.nextEvent(matching: .any, until: Date().addingTimeInterval(0.005), inMode: .default, dequeue: true) { app.sendEvent(event) }
    app.updateWindows()
}
probeTimer?.cancel()
if inputProbe { engine.sendDesktopControl(DesktopControlMessage(action: .end, token: probeToken)) }
engine.stop()
lock.lock(); let count = frames, presentations = shown, times = cursorTimes, imageTimes = frameTimes, fast = dedicated, metrics = latestMetrics, start = started; lock.unlock()
let elapsed = start.map { Double(monotonicNS() - $0)/1e9 } ?? 1
let gaps = zip(times.dropFirst(),times).map { Double($0.0-$0.1)/1e6 }.sorted()
print("RESULT version=\(AppVersion.current) frames=\(count) presented=\(presentations) fps=\(Double(count)/elapsed) metrics=\(metrics)")
print("RENDER RESULT accepted=\(view.acceptedFrames) backpressure=\(view.backpressureFrames)")
let imageGaps = zip(imageTimes.dropFirst(),imageTimes).map { Double($0.0-$0.1)/1e6 }.sorted()
let imageSpan = (imageTimes.first != nil && imageTimes.last != nil) ? Double(imageTimes.last!-imageTimes.first!)/1e9 : 0
print("IMAGE RESULT spanSeconds=\(imageSpan) p95GapMS=\(imageGaps.isEmpty ? 0 : imageGaps[min(imageGaps.count-1,Int(Double(imageGaps.count)*0.95))]) maxGapMS=\(imageGaps.last ?? 0)")
print("CURSOR RESULT dedicated=\(fast) samples=\(times.count) medianGapMS=\(gaps.isEmpty ? 0 : gaps[gaps.count/2]) p95GapMS=\(gaps.isEmpty ? 0 : gaps[min(gaps.count-1,Int(Double(gaps.count)*0.95))]) maxGapMS=\(gaps.last ?? 0)")
lock.lock(); let inputRTT = probeRTT.sorted(), inputSent = probeIndex; lock.unlock()
if inputProbe { print("INPUT RTT sent=\(inputSent) echoed=\(inputRTT.count) medianMS=\(inputRTT.isEmpty ? 0 : inputRTT[inputRTT.count/2]) p95MS=\(inputRTT.isEmpty ? 0 : inputRTT[min(inputRTT.count-1,Int(Double(inputRTT.count)*0.95))]) maxMS=\(inputRTT.last ?? 0)") }
window.close()
exit(count > 0 && presentations > 0 && view.acceptedFrames > 0 && (!inputProbe || inputRTT.count >= 100) ? 0 : 1)
