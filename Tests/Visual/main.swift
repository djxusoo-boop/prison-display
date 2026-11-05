import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let candidates = NSScreen.screens.filter { $0.localizedName.contains("PRISON DISPLAY") }
guard let screen = candidates.max(by: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0) < ($1.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0) }) else { print("No PRISON virtual screen available"); exit(1) }
let window = NSWindow(contentRect: NSRect(x: screen.frame.minX + 40, y: screen.frame.minY + 40, width: 500, height: 260), styleMask: [.borderless], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false; window.ignoresMouseEvents = true
let label = NSTextField(labelWithString: "PRISON DISPLAY · prueba de imagen")
label.frame = NSRect(x: 24, y: 90, width: 460, height: 60); label.font = .systemFont(ofSize: 22, weight: .bold); label.textColor = .white
window.contentView?.addSubview(label); window.orderFrontRegardless()
var count = 0
let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in
 count += 1; window.backgroundColor = NSColor(calibratedHue: CGFloat(count % 120) / 120, saturation: 0.7, brightness: 0.6, alpha: 1)
 label.stringValue = "PRISON DISPLAY · prueba \(count)"
}
RunLoop.current.run(until: Date().addingTimeInterval(8))
timer.invalidate(); window.orderOut(nil); window.close()
print("PASS: animated test pattern displayed only on PRISON virtual screen and removed")
