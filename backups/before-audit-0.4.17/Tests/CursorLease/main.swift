import AppKit
import CoreGraphics
setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 140), styleMask: [.titled], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
window.title = "PRISON DISPLAY · Prueba de cursor v\(AppVersion.current)"
window.contentView = NSTextField(wrappingLabelWithString: "Comprobación breve del cursor local. Se restaura al terminar. No se envía ni se genera entrada de ratón o teclado.")
let lease = LocalCursorLease()
var hideCalls = 0, showCalls = 0
lease.visibility = { hidden in
    if hidden { hideCalls += 1; NSCursor.hide() }
    else { showCalls += 1; NSCursor.unhide() }
}
var failures = 0
func check(_ value: Bool, _ name: String) { print("\(value ? "PASS" : "FAIL"): \(name)"); if !value { failures += 1 } }
func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if let event = app.nextEvent(matching: .any, until: min(end, Date().addingTimeInterval(0.01)), inMode: .default, dequeue: true) { app.sendEvent(event) }
        app.updateWindows()
    }
}
app.finishLaunching(); window.center(); window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
let deadline = Date().addingTimeInterval(3)
while !app.isActive && Date() < deadline { pump(0.02) }
check(app.isActive, "real foreground activation")
if app.isActive {
    for cycle in 1...5 {
        let acquired = lease.acquire()
        check(acquired && lease.detached && lease.hidden, "real Quartz cursor detachment cycle \(cycle)")
        if !acquired { break }
        defer { lease.release() }
        pump(0.05)
        check(lease.hidden && hideCalls == cycle, "one AppKit hide call per active lease")
        NSCursor.arrow.set(); pump(0.02)
        check(lease.hidden && lease.acquire() && hideCalls == cycle, "new cursor shape remains hidden without extra hide count")
        check(lease.release(), "physical cursor association restored")
        pump(0.02)
        check(!lease.hidden && !lease.detached && hideCalls == showCalls, "balanced AppKit restoration cycle \(cycle)")
    }
}
lease.release(); window.close()
print("RESULT: \(failures) failures; real cursor APIs; visual visibility requires physical observation; no event tap or synthetic input")
exit(failures == 0 ? 0 : 1)
