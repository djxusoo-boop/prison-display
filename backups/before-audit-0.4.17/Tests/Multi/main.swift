import AppKit
import Darwin
if CommandLine.arguments.contains("--virtual-display-helper") { exit(ADVirtualScreen.runHelper(CommandLine.arguments)) }
setbuf(stdout,nil)
umask(0o077)
if let path = CommandLine.arguments.first(where: { $0.hasPrefix("log=") }).map({ String($0.dropFirst(4)) }) { _ = freopen(path,"w",stdout); _ = freopen(path+".errors","w",stderr) }
let app = NSApplication.shared; app.setActivationPolicy(.accessory); app.finishLaunching()
let engines = [SenderEngine(),SenderEngine()]
let lock = NSLock()
var samples = [0,0], presented = [false,false], metrics = ["", ""]
var windows = [NSWindow](), timers = [Timer]()
var started = Date(), failures = 0, changed = false, stoppedSecond = false, firstAtStop = 0, completed = false
let directory = CommandLine.arguments[1]
func check(_ ok: Bool, _ message: String) { print(ok ? "PASS:" : "FAIL:",message); if !ok { failures += 1 } }
for index in 0..<2 {
    let engine = engines[index]; engine.screenSlot = index
    engine.cursorLocation = {
        let bounds = DisplayGeometry.shared.bounds(engine.pointer.displayID)
        let x = bounds.minX + bounds.width*(0.5+0.25*sin(Date().timeIntervalSinceReferenceDate*2))
        return CGPoint(x:x,y:bounds.midY)
    }
    engine.discoveryLabel = "PRISON DISPLAY · Prueba pantalla \(index+1)"
    engine.pointer.post = { _ in }; engine.keyboard.post = { _ in }
    engine.pointer.trusted = { true }; engine.desktopPermission = { true }
    engine.onLink = { link in if let link = link { try! link.url.absoluteString.write(toFile: directory+"/screen\(index+1).link",atomically:true,encoding:.utf8) } }
    engine.onStatus = { print("SCREEN",index+1,$0) }
    engine.onFirstImage = { lock.lock(); presented[index] = true; lock.unlock(); print("FIRST IMAGE", index+1) }
    engine.onFrameRoundTrip = { _ in lock.lock(); samples[index] += 1; lock.unlock() }
    engine.onMetrics = { value in lock.lock(); metrics[index] = value; lock.unlock() }
    engine.onSessionActive = {
        DispatchQueue.main.async {
            let bounds = DisplayGeometry.shared.bounds(engine.pointer.displayID)
            guard !bounds.isEmpty else { return }
            let origin = NSPoint(x: bounds.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0)-bounds.maxY)
            let window = NSWindow(contentRect: NSRect(origin: origin, size: NSSize(width: min(1100,bounds.width),height:min(700,bounds.height))), styleMask: [.borderless],backing:.buffered,defer:false)
            window.isReleasedWhenClosed = false; window.backgroundColor = NSColor(calibratedWhite:0.09,alpha:1)
            let view = NSView(frame: window.contentView!.bounds); view.wantsLayer = true; view.layer?.backgroundColor = NSColor(calibratedWhite:0.09,alpha:1).cgColor
            let label = NSTextField(labelWithString: "PRISON DISPLAY · Pantalla \(index+1) · Prueba de movimiento")
            label.font = .systemFont(ofSize:28); label.textColor = .white; label.frame = NSRect(x:20,y:20,width:1000,height:45); view.addSubview(label)
            let bar = NSView(frame:NSRect(x:10,y:100,width:80,height:300)); bar.wantsLayer = true; bar.layer?.backgroundColor = (index == 0 ? NSColor.systemPurple : NSColor.systemBlue).cgColor; view.addSubview(bar)
            window.contentView = view; window.orderFrontRegardless(); windows.append(window)
            let timer = Timer.scheduledTimer(withTimeInterval:1.0/30,repeats:true) { _ in bar.setFrameOrigin(NSPoint(x:20+CGFloat((sin(Date().timeIntervalSinceReferenceDate*3)+1)/2)*850,y:100)) }; timers.append(timer)
        }
    }
    try engine.start(key: newPairingKey(),options:StreamOptions(extend:true,width:1920,height:1080,fps:60,bitrate:20_000_000))
}
let timer = Timer.scheduledTimer(withTimeInterval:0.2,repeats:true) { _ in
    if completed { return }
    lock.lock(); let ready = presented.allSatisfy { $0 }; let counts = samples; lock.unlock()
    if !ready { started = Date(); return }
    let elapsed = Date().timeIntervalSince(started)
    if elapsed > 12 && !changed {
        changed = true; engines[0].update(options:StreamOptions(extend:true,width:1280,height:720,fps:30,bitrate:12_000_000)); print("ACTION resize first, second remains live")
    }
    if elapsed > 23 && !stoppedSecond {
        stoppedSecond = true; firstAtStop = counts[0]; engines[1].stop(); print("ACTION stop second, first remains live")
    }
    if elapsed > 32 {
        completed = true
        check(counts[0] > 200 && counts[1] > 200,"both real receivers acknowledge continuous images")
        check(counts[0] > firstAtStop+30,"first receiver continues after second disconnects")
        lock.lock(); print("ACK COUNTS",samples); print("METRICS",metrics); lock.unlock()
        for engine in engines { engine.stop() }
        for timer in timers { timer.invalidate() }; for window in windows { window.close() }
        DispatchQueue.main.asyncAfter(deadline:.now()+2) { print("RESULT",failures,"failures"); exit(failures == 0 ? 0 : 1) }
    }
}
// Deadline catches unavailable devices instead of hanging indefinitely.
DispatchQueue.main.asyncAfter(deadline:.now()+100) { check(false,"two receivers started within deadline"); for engine in engines { engine.stop() }; exit(1) }
app.run()
