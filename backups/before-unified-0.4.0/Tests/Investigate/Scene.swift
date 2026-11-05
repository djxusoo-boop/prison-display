import AppKit
import QuartzCore

// A repeatable moving desktop fixture; it never synthesizes mouse or keyboard input.
final class DiagnosticScene: NSView {
    static var window: NSWindow?
    static var refresh: Timer?
    static var ticks = 0
    static func show(frame requestedFrame: NSRect? = nil) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let frame = requestedFrame ?? NSScreen.main!.visibleFrame
        Self.refresh?.invalidate(); Self.refresh = nil
        Self.window?.close()
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "PRISON DISPLAY · Prueba temporal de imagen"
        let view = DiagnosticScene(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = view
        window.level = .floating
        window.orderFrontRegardless()
        Self.window = window
        view.wantsLayer = true
        let marker = CALayer()
        marker.backgroundColor = NSColor.systemPurple.cgColor
        marker.frame = CGRect(x: 0, y: 0, width: 8, height: frame.height)
        view.layer!.addSublayer(marker)
        let motion = CABasicAnimation(keyPath: "position.x")
        motion.fromValue = 4; motion.toValue = frame.width - 4
        motion.duration = 2; motion.autoreverses = true
        motion.repeatCount = .infinity
        motion.timingFunction = CAMediaTimingFunction(name: .linear)
        marker.add(motion, forKey: "motion")
        // CoreAnimation may suspend autonomous animations on a virtual monitor.
        // Drive our fixture explicitly so an idle capture is never mistaken for
        // a sustained motion trial. No system input or other windows are used.
        marker.removeAnimation(forKey: "motion")
        let began = ProcessInfo.processInfo.systemUptime
        Self.refresh = Timer.scheduledTimer(withTimeInterval: 1.0/60, repeats: true) { _ in
            let phase = (ProcessInfo.processInfo.systemUptime-began).truncatingRemainder(dividingBy: 4)
            let fraction = phase < 2 ? phase/2 : (4-phase)/2
            CATransaction.begin(); CATransaction.setDisableActions(true)
            marker.position.x = 4 + (frame.width-8)*fraction
            CATransaction.commit(); CATransaction.flush()
            Self.ticks += 1
        }
        if CommandLine.arguments.contains("detail") {
            // A scrolling arrangement fixture: generated text, grid and waveforms.
            let image = NSImage(size: frame.size)
            image.lockFocus()
            NSColor(calibratedWhite: 0.09, alpha: 1).setFill()
            NSRect(origin: .zero, size: frame.size).fill()
            for row in 0..<Int(frame.height / 28) {
                let y = CGFloat(row * 28)
                "Pista \(row)  PRISON DISPLAY  0123456789".draw(at: CGPoint(x: 20, y: y), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 17, weight: .regular), .foregroundColor: NSColor.white])
                let path = NSBezierPath(); path.lineWidth = 1
                for x in stride(from: 440, to: Int(frame.width), by: 2) {
                    let amplitude = sin(Double(x * (row+3))*0.035)*11
                    let point = CGPoint(x: CGFloat(x), y: y + 14 + CGFloat(amplitude))
                    if x == 440 { path.move(to: point) } else { path.line(to: point) }
                }
                NSColor(calibratedHue: CGFloat(row % 8)/8, saturation: 0.6, brightness: 0.85, alpha: 1).setStroke(); path.stroke()
            }
            image.unlockFocus()
            let moving = CALayer(); moving.frame = CGRect(origin: .zero, size: frame.size)
            moving.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            view.layer!.insertSublayer(moving, below: marker)
            let scroll = CABasicAnimation(keyPath: "position.x")
            scroll.fromValue = frame.width/2; scroll.toValue = frame.width/2 - 100
            scroll.duration = 2; scroll.autoreverses = true; scroll.repeatCount = .infinity
            scroll.timingFunction = CAMediaTimingFunction(name: .linear)
            moving.add(scroll, forKey: "scroll")
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.08, alpha: 1).setFill(); bounds.fill()
        let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 28, weight: .bold), .foregroundColor: NSColor.white]
        let text: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 17, weight: .regular), .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1)]
        "PRISON DISPLAY · Movimiento de prueba".draw(at: CGPoint(x: 32, y: bounds.height - 62), withAttributes: title)
        for row in 0..<Int((bounds.height - 100) / 28) {
            let y = bounds.height - 102 - CGFloat(row * 28)
            "\(String(format: "%02d", row))  Ventanas · texto pequeño · 1920 × 1080 · 60 FPS · mismo contenido".draw(at: CGPoint(x: 32, y: y), withAttributes: text)
        }
    }
}
