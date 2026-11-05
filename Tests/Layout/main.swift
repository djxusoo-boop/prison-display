import AppKit
#if SENDER
if CommandLine.arguments.contains("--virtual-display-helper") { exit(ADVirtualScreen.runHelper(CommandLine.arguments)) }
#endif
var failures = 0
func check(_ result: Bool, _ name: String) { print(result ? "PASS:" : "FAIL:", name); if !result { failures += 1 } }
let app = NSApplication.shared
let controller = AppController()
controller.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
guard let scroll = controller.window.contentView?.subviews.first as? NSScrollView,
      let document = scroll.documentView,
      let root = document.subviews.first as? NSStackView else { fatalError("missing scroll layout") }
func pump(until: () -> Bool, seconds: Double = 2) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !until() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    return until()
}
// Synthetic reads only: these flows never touch the production Keychain.
controller.recoverConnection.isHidden = false; controller.recoverConnectionRow?.isHidden = false
controller.rememberConnection.state = .off
controller.loadRememberedConnection = { allowed in
    guard allowed else { throw AireError("Unexpected passive read") }
    throw AireError("Synthetic authorization cancelled")
}
controller.restoreRememberedConnection()
check(!controller.recoverConnection.isEnabled && !controller.rememberConnection.isEnabled,
      "explicit recovery disables duplicate requests while keeping the main thread available")
controller.restoreRememberedConnection()
check(pump(until: { controller.recoverConnection.isEnabled }) && controller.trustExplanation.stringValue.contains("Synthetic"),
      "cancelled authorization reports once and permits an explicit retry")
check(controller.rememberConnection.state == .off, "failed authorization does not claim the connection is remembered")
controller.loadRememberedConnection = { _ in nil }
controller.restoreRememberedConnection()
check(pump(until: { controller.recoverConnection.isEnabled }) && controller.trustExplanation.stringValue.contains("Primera conexión"),
      "missing item leaves ordinary connection available without inventing credentials")
let entered = DispatchSemaphore(value: 0), released = DispatchSemaphore(value: 0), returned = DispatchSemaphore(value: 0)
let saved = try TrustedProfile(ConnectionLink(host: "synthetic.local", port: 55000, key: newPairingKey(), serviceName: "synthetic"))
controller.loadRememberedConnection = { _ in entered.signal(); released.wait(); returned.signal(); return saved }
controller.restoreRememberedConnection()
check(entered.wait(timeout: .now()+2) == .success, "authorization runs off the UI thread")
controller.stop()
check(!controller.recoverConnection.isEnabled, "stop cannot enqueue another read while the system authorization is still pending")
released.signal()
_ = returned.wait(timeout: .now()+2)
_ = pump(until: { controller.rememberConnection.state == .on }, seconds: 0.1)
check(controller.rememberConnection.state == .off,
      "stop ignores a late authorization result instead of restarting a connection")
#if SENDER
for selected in VideoQualityProfile.all.indices {
    controller.quality.selectItem(at: selected)
    check(controller.selectedOptions().bitrate == VideoQualityProfile.all[selected].ceiling, "quality menu maps to the requested bitrate ceiling")
}
for selected in 0..<2 {
    controller.fps.selectItem(at: selected)
    check(controller.selectedOptions().fps == (selected == 0 ? 60 : 30), "FPS menu maps to capture configuration")
    controller.mode.selectItem(at: selected)
    check(controller.selectedOptions().extend == (selected == 0), "display menu maps to extension/mirroring")
    controller.cursorStyle.selectItem(at: selected)
    check(controller.selectedOptions().nativeCursor == (selected == 1), "cursor menu maps to embedded/independent cursor")
}
check(controller.resolution.numberOfItems == 3, "remote resolution menu preserves its compatible profiles")
check(controller.localResolution.numberOfItems == 3, "local HDMI menu exposes three high-resolution virtual profiles")
controller.localResolution.selectItem(at: 2)
check(DisplayResolutionProfile.local[controller.localResolution.indexOfSelectedItem].width == 3840, "local HDMI 4K choice maps to a 3840x2160 virtual desktop")
controller.mode.selectItem(at: 0);controller.fps.selectItem(at: 0);controller.cursorStyle.selectItem(at: 0);controller.quality.selectItem(at: 2)
#endif
for width: CGFloat in [600, 660, 900] {
    controller.status.stringValue = width == 600 ? "No se pudo conectar con el MacBook. Comprueba que las dos apps están abiertas, usan la misma versión y que ambos equipos están conectados a tu red Wi-Fi." : "Listo."
    controller.metrics.isHidden = width != 600
    controller.metrics.stringValue = width == 600 ? "60 FPS · H.264 hardware · decod. 2.5 ms · 1920 × 1080 · Conexión Wi-Fi cifrada · v\(AppVersion.current)" : ""
    controller.window.setContentSize(NSSize(width: width, height: 650))
    controller.window.contentView?.layoutSubtreeIfNeeded()
    root.setFrameSize(NSSize(width: width, height: root.fittingSize.height))
    root.layoutSubtreeIfNeeded()
    var previous: NSView?
    for view in root.arrangedSubviews where !view.isHidden {
        check(view.frame.height >= 12, "section has an explicit noncollapsed height at width \(width)")
        if let previous = previous {
            check(view.frame.minY >= previous.frame.maxY + 5, "sections do not overlap at width \(width)")
        }
        previous = view
        if let inner = view.subviews.first as? NSStackView {
            check(view.frame.height >= inner.fittingSize.height + 35, "card respects content and padding at width \(width)")
            for child in inner.arrangedSubviews where !child.isHidden {
                let aligned = child.alignmentRect(forFrame: child.frame)
                if !(aligned.maxX <= inner.bounds.width + 1 && aligned.width > 0) { print("GEOMETRY", type(of: child), child.frame, aligned, inner.bounds) }
                check(aligned.maxX <= inner.bounds.width + 1 && aligned.width > 0, "control/text stays within card at width \(width)")
                if let label = child as? NSTextField {
                    check(label.frame.height + 1 >= label.fittingSize.height, "wrapped text is not vertically compressed at width \(width)")
                }
            }
        }
    }
    check(root.frame.height >= root.fittingSize.height - 1, "small window retains content height instead of piling controls")
}
controller.loadRememberedConnection = { _ in saved }
controller.restoreRememberedConnection()
check(pump(until: { controller.rememberConnection.state == .on }) && controller.recoverConnection.isHidden,
      "successful explicit read restores remembered state and removes the recovery action")
for phase in [StreamPhase.available, .connecting, .preparing, .streaming, .applying, .reconnecting, .failed, .idle] {
    controller.displayPhase(phase)
    check(controller.connectionState.stringValue == phase.title, "connection badge distinguishes \(phase)")
}
controller.displayPhase(.streaming)
check(!controller.primary.isEnabled && controller.disconnect.isEnabled && controller.primary.title.contains("Conectado"),
      "live connection disables duplicate connect and keeps disconnect available")
controller.displayPhase(.reconnecting)
check(!controller.primary.isEnabled && controller.disconnect.isEnabled,
      "automatic reconnection cannot be restarted by duplicate connect clicks")
#if SENDER
controller.engine.screenPermission = { false }
controller.start()
check(pump(until: { controller.connectionState.stringValue == StreamPhase.failed.title }),
      "queued stop cannot overwrite a failed start with a disconnected badge")
#else
controller.engine.reportStartFailure("Synthetic cancelled pairing")
check(pump(until: { controller.connectionState.stringValue == StreamPhase.failed.title }) && controller.status.stringValue.contains("Synthetic"),
      "failed pairing keeps engine and UI in the same recoverable state")
controller.engine.beginPairing()
check(pump(until: { controller.connectionState.stringValue == StreamPhase.connecting.title }) && !controller.primary.isEnabled,
      "pairing keeps the connecting badge after retiring the old session")
controller.engine.stop()
check(pump(until: { controller.connectionState.stringValue == StreamPhase.idle.title }),
      "stopping pairing returns controls to disconnected state")
#endif
controller.displayPhase(.reconnecting)
check(!controller.inputState.stringValue.isEmpty, "connection loss retains an independent input status")
#if !SENDER
controller.keyboardSwitch.state = .on; controller.toggleKeyboard(controller.keyboardSwitch)
controller.displayPhase(.preparing)
check(controller.inputState.stringValue.contains("esperando"), "keyboard selection does not claim readiness before an image")
controller.keyboardSwitch.state = .off; controller.toggleKeyboard(controller.keyboardSwitch)
#endif
controller.status.stringValue = "Listo."; controller.metrics.stringValue = ""; controller.metrics.isHidden = true
controller.window.setContentSize(NSSize(width: 660, height: 980))
controller.window.contentView?.layoutSubtreeIfNeeded()
root.setFrameSize(NSSize(width: 660, height: root.fittingSize.height))
root.layoutSubtreeIfNeeded()
if let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
    root.cacheDisplay(in: root.bounds, to: rep)
    let path = CommandLine.arguments.last!
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("PREVIEW", path, "height", root.frame.height)
}
print("RESULT", failures, "failures")
exit(failures == 0 ? 0 : 1)
