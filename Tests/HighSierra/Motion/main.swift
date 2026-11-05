import AppKit
import QuartzCore
func prisonMonoFont(_ size: CGFloat) -> NSFont { NSFont(name: "Menlo", size: size) ?? NSFont.systemFont(ofSize: size) }
final class MotionDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticScene.show()
        NSApp.setActivationPolicy(.regular)
        DiagnosticScene.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Timer.scheduledTimer(withTimeInterval: 90, repeats: false) { _ in
            DiagnosticScene.refresh?.invalidate(); DiagnosticScene.window?.close(); NSApp.terminate(nil)
        }
    }
}
let app = NSApplication.shared
let delegate = MotionDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
