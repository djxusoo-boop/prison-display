#if UNIFIED && !LEGACY
import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

// `--correction-self-test <folder>`: drives the real compositor on the
// connected monitor, shows a test pattern on the corrected desktop, captures
// what the monitor actually receives and checks it pixel by pixel. Saves one
// PNG per case. The Mac's built-in display is never changed.
@available(macOS 14.0, *)
final class CorrectionSelfTest: NSObject, NSApplicationDelegate {
    struct Case { let name: String; let settings: CorrectionSettings }
    private let folder: URL
    private let engine = CorrectionEngine()
    private var pattern: NSWindow?
    private var failures = 0, checks = 0
    private var report: [String] = []
    init(folder: URL) { self.folder = folder }

    static func run(folder: URL) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let test = CorrectionSelfTest(folder: folder)
        app.delegate = test
        app.run()
        exit(1)
    }
    private func check(_ ok: Bool, _ title: String) {
        checks += 1; if !ok { failures += 1 }
        let line = (ok ? "PASS: " : "FAIL: ") + title; print(line); report.append(line)
    }
    private func finish() -> Never {
        let summary = "RESULT \(checks) checks \(failures) failures"
        print(summary); report.append(summary)
        try? report.joined(separator: "\n").write(to: folder.appendingPathComponent("resultado.txt"), atomically: true, encoding: .utf8)
        exit(failures == 0 ? 0 : 1)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        DispatchQueue.main.async { self.start() }
    }
    private func start() {
        guard let monitor = CorrectionDisplays.candidates().first else { check(false, "hay un monitor externo ampliado"); finish() }
        let builtin = CGMainDisplayID()
        let originalOrigin = CGDisplayBounds(monitor).origin
        let modeBefore = CorrectionDisplays.modeText(monitor)
        print("Monitor: \(CorrectionDisplays.name(monitor)) · \(modeBefore)")
        // Fixed geometry cases first (signal not stretched), then the TV's own shape.
        var base = CorrectionSettings(); base.desktopWidth = 1920; base.desktopHeight = 1080; base.screenAspect = 1.25
        if let error = engine.start(display: monitor, settings: base) { check(false, "la corrección arranca: \(error)"); finish() }
        check(true, "la corrección arranca en \(CorrectionDisplays.name(monitor))")
        let mode = CGDisplayCopyDisplayMode(monitor)
        check(mode?.pixelWidth == 1280 && mode?.pixelHeight == 1024, "la salida física sigue en 1280 × 1024 (\(CorrectionDisplays.modeText(monitor)))")
        report.append("Frecuencia: \(CorrectionDisplays.modeText(monitor))" + (engine.note.isEmpty ? "" : " · \(engine.note)"))
        check(CorrectionDisplays.isOnline(builtin) && CGDisplayMirrorsDisplay(builtin) == kCGNullDirectDisplay && CGMainDisplayID() == builtin, "la pantalla del Mac sigue visible, sin duplicar y como principal")

        var margins = base; margins.left = 40; margins.right = 80; margins.top = 30; margins.bottom = 60
        var moved = base; moved.scale = 0.7; moved.offsetX = 100; moved.offsetY = -50
        var corner = base; corner.scale = 0.5; corner.offsetX = 5000; corner.offsetY = 5000
        var big = base; big.scale = 1.5
        var tall = base; tall.desktopWidth = 1920; tall.desktopHeight = 1200
        var tv = base; tv.screenAspect = nil
        let cases = [Case(name: "1-centrado", settings: base), Case(name: "2-margenes", settings: margins), Case(name: "3-escala-y-desplazamiento", settings: moved),
                     Case(name: "4-esquina-sin-cortar", settings: corner), Case(name: "5-escala-maxima-sin-cortar", settings: big), Case(name: "6-escritorio-16x10", settings: tall), Case(name: "7-forma-real-de-la-TV", settings: tv)]
        var index = 0
        func next() {
            guard index < cases.count else { return pointerAndStop(monitor: monitor, origin: originalOrigin) }
            let item = cases[index]; index += 1
            let before = engine.framesShown
            engine.update(item.settings)
            // A new desktop size recreates the virtual display: wait for its first images.
            CorrectionEngine.waitAsync(seconds: 20, until: { self.engine.active && !self.engine.restarting && self.engine.canvasVisible && (self.engine.framesShown > 3 || self.engine.framesShown > before) }) { _ in
                self.showPattern()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    self.verify(item, monitor: monitor) { next() }
                }
            }
        }
        next()
    }

    // Grey desktop, coloured corners and a white centre: shows position, size,
    // proportion and that nothing is cut.
    private func showPattern() {
        let bounds = CGDisplayBounds(engine.virtualID), primary = CGDisplayBounds(CGMainDisplayID())
        let frame = NSRect(x: bounds.minX, y: primary.height - bounds.maxY, width: bounds.width, height: bounds.height)
        if pattern == nil {
            let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver; window.isOpaque = true; window.ignoresMouseEvents = true; window.isReleasedWhenClosed = false
            window.contentView = PatternView(); pattern = window
        }
        pattern?.setFrame(frame, display: true); pattern?.orderFrontRegardless()
    }

    private func verify(_ item: Case, monitor: CGDirectDisplayID, then: @escaping () -> Void) {
        let frame = CGDisplayBounds(monitor).size
        check(engine.canvasVisible, "\(item.name): la imagen corregida está en pantalla en el monitor")
        let physical = CorrectionDisplays.physicalAspect(monitor)
        let expected = CorrectionSettings.layout(frame: frame, desktop: CGSize(width: item.settings.desktopWidth, height: item.settings.desktopHeight), settings: item.settings, physicalAspect: physical)
        let k = CorrectionSettings.stretch(frame: frame, settings: item.settings, physicalAspect: physical)
        check(engine.imageRect == expected, "\(item.name): el compositor usa el rectángulo calculado \(Int(expected.width))×\(Int(expected.height)) en (\(Int(expected.minX)), \(Int(expected.minY)))")
        check(expected.minX >= 0 && expected.minY >= 0 && expected.maxX <= frame.width && expected.maxY <= frame.height, "\(item.name): la imagen cabe entera en el monitor")
        let ratio = (expected.width * k / expected.height) / (CGFloat(item.settings.desktopWidth) / CGFloat(item.settings.desktopHeight))
        check(abs(ratio - 1) < 0.01, "\(item.name): en la pantalla se ve con la proporción del escritorio (estirado de la TV ×\(String(format: "%.3f", k)), proporción \(String(format: "%.3f", ratio)))")
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, _ in
            guard let display = content?.displays.first(where: { $0.displayID == monitor }) else {
                DispatchQueue.main.async { self.check(false, "\(item.name): capturar la salida del monitor"); then() }
                return
            }
            let config = SCStreamConfiguration(); config.width = Int(frame.width); config.height = Int(frame.height); config.showsCursor = false
            SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: config) { image, error in
                DispatchQueue.main.async {
                    guard let image = image else { self.check(false, "\(item.name): capturar la salida del monitor (\(error?.localizedDescription ?? "-"))"); then(); return }
                    self.save(image, name: item.name)
                    self.analyse(image, rect: expected, name: item.name)
                    then()
                }
            }
        }
    }
    private func analyse(_ image: CGImage, rect: CGRect, name: String) {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { check(false, "\(name): leer la imagen"); return }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Context rows start at the top for this bitmap layout.
        func px(_ x: CGFloat, _ y: CGFloat) -> (Int, Int, Int) {
            let ix = min(max(0, Int(x)), w - 1), iy = min(max(0, Int(y)), h - 1), i = (iy * w + ix) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
        }
        func inside(_ fx: CGFloat, _ fy: CGFloat) -> (Int, Int, Int) { px(rect.minX + rect.width * fx, rect.minY + rect.height * fy) }
        let red = inside(0.035, 0.06), green = inside(0.965, 0.06), blue = inside(0.035, 0.94), yellow = inside(0.965, 0.94), white = inside(0.5, 0.5), grey = inside(0.5, 0.25)
        check(red.0 > 150 && red.1 < 90 && red.2 < 90, "\(name): esquina superior izquierda en su sitio \(red)")
        check(green.1 > 150 && green.0 < 110 && green.2 < 110, "\(name): esquina superior derecha en su sitio \(green)")
        check(blue.2 > 150 && blue.0 < 90 && blue.1 < 110, "\(name): esquina inferior izquierda en su sitio \(blue)")
        check(yellow.0 > 150 && yellow.1 > 150 && yellow.2 < 110, "\(name): esquina inferior derecha en su sitio \(yellow)")
        check(white.0 > 200 && white.1 > 200 && white.2 > 200, "\(name): centro en su sitio \(white)")
        check(abs(grey.0 - grey.2) < 40 && grey.0 > 60 && grey.0 < 200, "\(name): fondo de prueba sin deformar \(grey)")
        // Everything outside the rectangle is black.
        var outside: [(CGFloat, CGFloat)] = []
        let W = CGFloat(w), H = CGFloat(h)
        for f in [0.1, 0.5, 0.9] as [CGFloat] {
            if rect.minY > 8 { outside.append((W * f, rect.minY / 2)) }
            if H - rect.maxY > 8 { outside.append((W * f, (rect.maxY + H) / 2)) }
            if rect.minX > 8 { outside.append((rect.minX / 2, H * f)) }
            if W - rect.maxX > 8 { outside.append(((rect.maxX + W) / 2, H * f)) }
        }
        let lit = outside.map { px($0.0, $0.1) }.filter { max($0.0, $0.1, $0.2) > 30 }
        check(lit.isEmpty, "\(name): bordes negros fuera de la imagen (\(outside.count) puntos)")
        // Just inside each edge is the image, not black: nothing cut away.
        let edges = [inside(0.5, 0.004), inside(0.5, 0.996), inside(0.003, 0.5), inside(0.997, 0.5)]
        check(edges.allSatisfy { max($0.0, $0.1, $0.2) > 40 }, "\(name): la imagen llega a sus cuatro bordes \(edges)")
    }
    private func save(_ image: CGImage, name: String) {
        let url = folder.appendingPathComponent(name + ".png") as CFURL
        guard let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil); CGImageDestinationFinalize(destination)
    }
    private func pointerAndStop(monitor: CGDirectDisplayID, origin: CGPoint) {
        // The pointer cannot enter the raw monitor; put it back where it was.
        let saved = CGEvent(source: nil)?.location ?? .zero
        let bounds = CGDisplayBounds(monitor)
        CGWarpMouseCursorPosition(CGPoint(x: bounds.midX, y: bounds.midY))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let now = CGEvent(source: nil)?.location ?? .zero
            self.check(!bounds.contains(now), "el ratón no se queda en el monitor sin corregir")
            CGWarpMouseCursorPosition(saved); CGAssociateMouseAndMouseCursorPosition(1)
            self.pattern?.orderOut(nil)
            let virtualID = self.engine.virtualID
            self.engine.stop(reason: nil)
            CorrectionEngine.waitAsync(seconds: 15, until: { !CorrectionDisplays.isOnline(virtualID) }) { removed in
                self.check(removed, "al detener desaparece el escritorio virtual")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    let restored = CGDisplayBounds(monitor).origin
                    self.check(abs(restored.x - origin.x) < 2 && abs(restored.y - origin.y) < 2, "al detener el monitor vuelve a su sitio (\(Int(restored.x)), \(Int(restored.y)))")
                    self.finish()
                }
            }
        }
    }
}

private final class PatternView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1).setFill(); bounds.fill()
        let s = bounds.height * 0.15
        let squares: [(NSColor, NSRect)] = [
            (NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), NSRect(x: 0, y: bounds.height - s, width: s, height: s)),
            (NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1), NSRect(x: bounds.width - s, y: bounds.height - s, width: s, height: s)),
            (NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), NSRect(x: 0, y: 0, width: s, height: s)),
            (NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1), NSRect(x: bounds.width - s, y: 0, width: s, height: s)),
            (.white, NSRect(x: bounds.midX - s / 2, y: bounds.midY - s / 2, width: s, height: s)),
        ]
        for (color, rect) in squares { color.setFill(); rect.fill() }
        // A thin light frame on every edge of the desktop.
        NSColor(srgbRed: 0.85, green: 0.85, blue: 0.85, alpha: 1).setStroke()
        let frame = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2)); frame.lineWidth = 4; frame.stroke()
    }
}
#endif
