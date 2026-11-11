#if UNIFIED && !LEGACY
import AppKit
import Carbon.HIToolbox
import CoreMedia
import QuartzCore
import ScreenCaptureKit

// Corrected external monitor (for example a TV on VGA that only takes
// 1280 × 1024). The physical output keeps its own mode. The Mac's desktop
// lives on a virtual 16:9 display; this compositor captures it and draws it
// on the monitor inside a rectangle set by margins, scale and offset, with
// black borders around it. Nothing is stretched (the aspect ratio is kept) and
// nothing is cut (the rectangle always stays inside the monitor).

struct CorrectionSettings: Codable, Equatable {
    var desktopWidth = 1920, desktopHeight = 1080
    var scale = 1.0                      // 1 = as large as fits inside the margins
    var offsetX = 0.0, offsetY = 0.0     // monitor pixels; + right, + down
    var left = 0.0, right = 0.0, top = 0.0, bottom = 0.0   // monitor pixels
    // Shape of the visible picture (width / height). A TV often stretches a
    // 5:4 signal across a 16:9 panel; the image is pre-squeezed to match so it
    // looks right on the glass. nil = automatic (physical size from the monitor).
    var screenAspect: Double?
    // Only the width, in percent (nil = 100): narrows or widens the picture
    // without changing its height, to match the TV by eye.
    var width: Double?
    static let widthRange = 40.0...160.0
    static let screenAspects: [(String, Double?)] = [("Automática", nil), ("16:9 · TV panorámica", 16.0 / 9), ("16:10", 16.0 / 10), ("4:3", 4.0 / 3), ("5:4 · sin estirar", 5.0 / 4)]
    static let desktopSizes: [(Int, Int)] = [(1280, 720), (1600, 900), (1920, 1080), (2560, 1440), (1680, 1050), (1920, 1200)]
    static let scaleRange = 0.3...1.5
    // Keep the margins; put the image back in the middle at the largest size.
    mutating func centerAndFit() { scale = 1; offsetX = 0; offsetY = 0 }
    // The image rectangle on the monitor, top-left origin, whole pixels.
    // How much the monitor stretches the signal horizontally.
    static func stretch(frame: CGSize, settings: CorrectionSettings, physicalAspect: Double?) -> CGFloat {
        let signal = Double(max(1, frame.width) / max(1, frame.height))
        guard let aspect = settings.screenAspect ?? physicalAspect, aspect.isFinite, (0.5...3).contains(aspect) else { return 1 }
        return CGFloat(aspect / signal)
    }
    static func layout(frame: CGSize, desktop: CGSize, settings: CorrectionSettings, physicalAspect: Double? = nil) -> CGRect {
        let w = max(1, frame.width), h = max(1, frame.height)
        // In signal pixels the desktop is narrower by the monitor's own stretch,
        // so on the screen it keeps its real proportion.
        let k = stretch(frame: frame, settings: settings, physicalAspect: physicalAspect)
        let widthFactor = CGFloat(min(max((settings.width ?? 100).isFinite ? (settings.width ?? 100) : 100, widthRange.lowerBound), widthRange.upperBound) / 100)
        let dw = max(1, desktop.width / k * widthFactor), dh = max(1, desktop.height)
        func margin(_ v: Double, _ size: CGFloat) -> CGFloat { min(max(0, CGFloat(v.isFinite ? v : 0)), size * 0.4) }
        let l = margin(settings.left, w), r = margin(settings.right, w), t = margin(settings.top, h), b = margin(settings.bottom, h)
        let area = CGRect(x: l, y: t, width: max(1, w - l - r), height: max(1, h - t - b))
        let scale = CGFloat(min(max(settings.scale.isFinite ? settings.scale : 1, scaleRange.lowerBound), scaleRange.upperBound))
        // Same factor on both axes: never deformed. Capped by the whole monitor: never cut.
        let fit = min(area.width / dw, area.height / dh) * scale
        let factor = min(fit, w / dw, h / dh)
        let size = CGSize(width: min(w, (dw * factor).rounded()), height: min(h, (dh * factor).rounded()))
        var x = area.midX - size.width / 2 + CGFloat(settings.offsetX.isFinite ? settings.offsetX : 0)
        var y = area.midY - size.height / 2 + CGFloat(settings.offsetY.isFinite ? settings.offsetY : 0)
        x = min(max(0, x), w - size.width); y = min(max(0, y), h - size.height)
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }
}

enum CorrectionStore {
    static var defaults = UserDefaults.standard
    static func key(_ display: CGDirectDisplayID) -> String {
        String(format: "PrisonDisplay.correction.%x-%x-%x", CGDisplayVendorNumber(display), CGDisplayModelNumber(display), CGDisplaySerialNumber(display))
    }
    static func load(_ display: CGDirectDisplayID) -> CorrectionSettings {
        guard let data = defaults.data(forKey: key(display)), let saved = try? JSONDecoder().decode(CorrectionSettings.self, from: data) else { return CorrectionSettings() }
        return saved
    }
    static func save(_ settings: CorrectionSettings, for display: CGDirectDisplayID) {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: key(display)) }
    }
}

enum CorrectionDisplays {
    // From the live list: CGDisplayIsOnline can keep answering yes for a
    // display that has just been removed.
    static func isOnline(_ display: CGDirectDisplayID) -> Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32); var count: UInt32 = 0
        guard display != 0, CGGetOnlineDisplayList(32, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains(display)
    }
    // External physical monitors that can be corrected.
    static func candidates() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16); var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).filter { CGDisplayVendorNumber($0) != 0xA1DE && CGDisplayIsBuiltin($0) == 0 && CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
    }
    static func name(_ display: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens where (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display {
            if #available(macOS 10.15, *) { return screen.localizedName }
        }
        return "Monitor externo"
    }
    // Width / height of the visible picture from the monitor's physical size.
    static func physicalAspect(_ display: CGDirectDisplayID) -> Double? {
        let size = CGDisplayScreenSize(display)
        guard size.width > 50, size.height > 50 else { return nil }
        let aspect = Double(size.width / size.height)
        guard (1.0...2.5).contains(aspect) else { return nil }
        // Sizes come in whole centimetres: snap to the nearest usual shape.
        for usual in [16.0 / 9, 16.0 / 10, 4.0 / 3, 5.0 / 4, 21.0 / 9] where abs(aspect / usual - 1) < 0.02 { return usual }
        return aspect
    }
    static func aspectName(_ aspect: Double?) -> String {
        guard let a = aspect else { return "desconocida" }
        for (name, value) in [("16:9", 16.0 / 9), ("16:10", 1.6), ("4:3", 4.0 / 3), ("5:4", 1.25), ("21:9", 21.0 / 9)] where abs(a - value) < 0.04 { return name }
        return String(format: "%.2f:1", a)
    }
    static func modeText(_ display: CGDirectDisplayID) -> String {
        guard let mode = CGDisplayCopyDisplayMode(display) else { return "—" }
        return "\(mode.pixelWidth) × \(mode.pixelHeight) a \(Int(mode.refreshRate.rounded())) Hz"
    }
    // Same output size, 60 Hz when macOS offers it. Returns a note for the user.
    static func preferSixtyHertz(_ display: CGDirectDisplayID) -> String {
        guard let current = CGDisplayCopyDisplayMode(display) else { return "" }
        if Int(current.refreshRate.rounded()) == 60 { return "" }
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode]) ?? []
        guard let sixty = modes.first(where: { $0.pixelWidth == current.pixelWidth && $0.pixelHeight == current.pixelHeight && $0.width == current.width && Int($0.refreshRate.rounded()) == 60 && $0.isUsableForDesktopGUI() }) else {
            return "El monitor no ofrece \(current.pixelWidth) × \(current.pixelHeight) a 60 Hz a macOS; se mantiene a \(Int(current.refreshRate.rounded())) Hz."
        }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return "" }
        CGConfigureDisplayWithDisplayMode(config, display, sixty, nil)
        return CGCompleteDisplayConfiguration(config, .forSession) == .success ? "" : "macOS no aceptó 60 Hz; se mantiene a \(Int(current.refreshRate.rounded())) Hz."
    }
}

@available(macOS 12.3, *)
final class CorrectionEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    private(set) var physical: CGDirectDisplayID = 0
    private(set) var virtualID: CGDirectDisplayID = 0
    private(set) var settings = CorrectionSettings()
    private(set) var imageRect = CGRect.zero
    private(set) var framesShown = 0
    private(set) var note = ""
    var onStopped: ((String) -> Void)?
    var onRestarted: (() -> Void)?
    var active: Bool { virtual != nil }
    private var virtual: ADVirtualScreen?
    private var window: NSWindow?
    private let imageLayer = CALayer()
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "PrisonDisplay.corrector", qos: .userInteractive)
    private var guardTimer: Timer?
    private var physicalOrigin: CGPoint?
    private var resize: DispatchWorkItem?
    private var captureSize = CGSize.zero
    private let lock = NSLock()
    private var pending: IOSurfaceRef?
    private var scheduled = false
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?

    // Main thread. Returns an error message, or nil once the image is on the monitor.
    private(set) var restarting = false
    func start(display: CGDirectDisplayID, settings: CorrectionSettings, origin knownOrigin: CGPoint? = nil) -> String? {
        guard virtual == nil else { return "La corrección ya está activa." }
        guard CorrectionDisplays.isOnline(display), CGDisplayIsBuiltin(display) == 0, display != CGMainDisplayID(), CGDisplayMirrorsDisplay(display) == kCGNullDirectDisplay else {
            return "El monitor debe estar conectado como pantalla ampliada (no duplicada) y no puede ser la principal."
        }
        guard ScreenCaptureAccess.permitted() else {
            return "Falta el permiso de Grabación de pantalla para PRISON DISPLAY (Ajustes → Privacidad y seguridad)."
        }
        self.settings = settings; physical = display
        note = CorrectionDisplays.preferSixtyHertz(display)
        let origin = knownOrigin ?? CGDisplayBounds(display).origin
        let screen = ADVirtualScreen(); screen.screenSlot = 3
        var message: NSString?
        guard screen.createWidth(UInt(settings.desktopWidth), height: UInt(settings.desktopHeight), error: &message) else {
            return message as String? ?? "No se pudo crear el escritorio virtual."
        }
        let id = screen.displayID
        guard Self.wait(seconds: 4, until: { CorrectionDisplays.isOnline(id) && Int(CGDisplayPixelsWide(id)) == settings.desktopWidth }) else {
            screen.destroy()
            return "macOS no encendió el escritorio virtual. Este Mac admite dos pantallas externas y el monitor ya cuenta como una: detén las pantallas enviadas a otros Mac y vuelve a intentarlo."
        }
        virtual = screen; virtualID = id; physicalOrigin = origin
        arrange()
        showWindow()
        installHotKey()
        guardTimer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.keepPointerOut() }
        RunLoop.main.add(guardTimer!, forMode: .common)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        startCapture()
        return nil
    }

    func update(_ next: CorrectionSettings) {
        guard next != settings else { return }
        let sizeChanged = next.desktopWidth != settings.desktopWidth || next.desktopHeight != settings.desktopHeight
        settings = next
        if sizeChanged, active {
            // A new desktop size needs a new virtual display: remove the old one
            // first (the Mac allows two external displays), keep the monitor's
            // original place, then create the new one.
            let display = physical, origin = physicalOrigin, old = virtualID
            restarting = true
            stop(reason: nil, restoreOrigin: false)
            Self.waitAsync(seconds: 15, until: { !CorrectionDisplays.isOnline(old) }) { [weak self] _ in
                guard let self = self else { return }
                self.restarting = false
                if let error = self.start(display: display, settings: next, origin: origin) { self.onStopped?(error) }
                else { self.onRestarted?() }
            }
            return
        }
        applyLayout()
    }

    // Main thread. Restores the monitor as an ordinary extended display.
    func stop(reason: String? = "Corrección detenida.", restoreOrigin: Bool = true) {
        guard let screen = virtual else { return }
        NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        guardTimer?.invalidate(); guardTimer = nil
        removeHotKey()
        if let stream = stream { self.stream = nil; stream.stopCapture { _ in } }
        resize?.cancel(); resize = nil
        window?.orderOut(nil); window = nil
        imageLayer.contents = nil
        virtual = nil
        let id = virtualID; virtualID = 0
        screen.destroy()
        // Put the monitor back once macOS has removed the virtual desktop. Waiting
        // without blocking: the removal is reported through this same thread.
        let monitor = physical, origin = restoreOrigin ? physicalOrigin : nil
        Self.waitAsync(seconds: 15, until: { !CorrectionDisplays.isOnline(id) }) { _ in
            guard let origin = origin, CorrectionDisplays.isOnline(monitor) else { return }
            var config: CGDisplayConfigRef?
            if CGBeginDisplayConfiguration(&config) == .success {
                CGConfigureDisplayOrigin(config, monitor, Int32(origin.x), Int32(origin.y))
                CGCompleteDisplayConfiguration(config, .forSession)
            }
        }
        physicalOrigin = nil; framesShown = 0
        if let reason = reason { onStopped?(reason) }
    }

    // The virtual desktop takes the monitor's place in the arrangement; the
    // monitor itself moves just beyond it, where the pointer is kept out.
    private func arrange() {
        guard let origin = physicalOrigin else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        CGConfigureDisplayOrigin(config, virtualID, Int32(origin.x), Int32(origin.y))
        CGConfigureDisplayOrigin(config, physical, Int32(origin.x) + Int32(settings.desktopWidth), Int32(origin.y))
        CGCompleteDisplayConfiguration(config, .forSession)
        _ = Self.wait(seconds: 2) { CGDisplayBounds(self.virtualID).origin == origin }
    }
    private func physicalFrameInCocoa() -> NSRect {
        let bounds = CGDisplayBounds(physical), primary = CGDisplayBounds(CGMainDisplayID())
        return NSRect(x: bounds.minX, y: primary.height - bounds.maxY, width: bounds.width, height: bounds.height)
    }
    private func showWindow() {
        let window = NSPanel(contentRect: physicalFrameInCocoa(), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.setFrame(physicalFrameInCocoa(), display: false)
        // Above the Dock and menu bar of that monitor. (The shielding level is
        // reserved for captured displays and is never shown or captured.)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true; window.isOpaque = true; window.hasShadow = false
        window.backgroundColor = .black; window.isReleasedWhenClosed = false; window.animationBehavior = .none
        let view = NSView(frame: NSRect(origin: .zero, size: window.frame.size)); view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        imageLayer.backgroundColor = NSColor.black.cgColor
        imageLayer.contentsGravity = .resize; imageLayer.magnificationFilter = .linear; imageLayer.minificationFilter = .linear
        imageLayer.actions = ["contents": NSNull(), "frame": NSNull(), "bounds": NSNull(), "position": NSNull()]
        view.layer?.addSublayer(imageLayer)
        window.contentView = view
        window.orderFrontRegardless()
        self.window = window
        applyLayout()
        // macOS finishes moving the displays after the configuration returns;
        // place the canvas again once the new arrangement is known.
        for delay in [0.3, 1.0, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.reassertWindow() }
        }
    }
    private func reassertWindow() {
        guard let window = window else { return }
        window.setFrame(physicalFrameInCocoa(), display: true)
        window.orderFrontRegardless()
        applyLayout()
    }
    // Whether the canvas is really on the monitor (for the status and the self-test).
    var canvasVisible: Bool {
        guard let window = window else { return false }
        let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(window.windowNumber)) as? [[String: Any]] ?? []
        return list.first?[kCGWindowIsOnscreen as String] as? Bool ?? false
    }
    private func applyLayout() {
        guard let window = window else { return }
        if window.frame != physicalFrameInCocoa() { window.setFrame(physicalFrameInCocoa(), display: true) }
        let frame = CGDisplayBounds(physical).size
        let scale = window.backingScaleFactor
        let rect = CorrectionSettings.layout(frame: CGSize(width: frame.width * scale, height: frame.height * scale), desktop: CGSize(width: settings.desktopWidth, height: settings.desktopHeight), settings: settings, physicalAspect: CorrectionDisplays.physicalAspect(physical))
        imageRect = rect
        CATransaction.begin(); CATransaction.setDisableActions(true)
        // Layer coordinates have their origin at the bottom; the rectangle at the top.
        imageLayer.frame = CGRect(x: rect.minX / scale, y: (frame.height * scale - rect.maxY) / scale, width: rect.width / scale, height: rect.height / scale)
        imageLayer.contentsScale = scale
        CATransaction.commit()
        // Capture at the drawn size: one GPU scale, sharp text. Collapse slider movement.
        resize?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.resizeCapture(to: rect.size) }
        resize = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func configuration(size: CGSize) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = max(2, Int(size.width) & ~1); config.height = max(2, Int(size.height) & ~1)
        config.minimumFrameInterval = CMTimeMake(value: 1, timescale: 60)
        config.queueDepth = 5; config.showsCursor = true; config.pixelFormat = kCVPixelFormatType_32BGRA
        // The output may be narrower than the desktop on purpose (a TV that
        // stretches it back); macOS must fill it, not add its own black bars.
        if #available(macOS 14.0, *) { config.preservesAspectRatio = false }
        return config
    }
    private func startCapture() {
        let id = virtualID, size = imageRect.size
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [weak self] content, error in
            DispatchQueue.main.async {
                guard let self = self, self.virtualID == id else { return }
                guard let display = content?.displays.first(where: { $0.displayID == id }) else {
                    self.stop(reason: "No se pudo capturar el escritorio virtual: \(error?.localizedDescription ?? "no aparece en macOS").")
                    return
                }
                let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: self.configuration(size: size), delegate: self)
                do { try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue) }
                catch { self.stop(reason: "No se pudo capturar: \(error.localizedDescription)"); return }
                self.stream = stream; self.captureSize = size
                stream.startCapture { error in
                    if let error = error { DispatchQueue.main.async { self.stop(reason: "macOS no dejó capturar el escritorio: \(error.localizedDescription)") } }
                }
            }
        }
    }
    private func resizeCapture(to size: CGSize) {
        guard let stream = stream, size != captureSize else { return }
        captureSize = size
        stream.updateConfiguration(configuration(size: size)) { _ in }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.stop(reason: "La captura se detuvo: \(error.localizedDescription)") }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer),
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pixel = CMSampleBufferGetImageBuffer(sampleBuffer), let surface = CVPixelBufferGetIOSurface(pixel)?.takeUnretainedValue() else { return }
        // Only the newest image waits for the main thread; older ones are dropped.
        lock.lock(); pending = surface; let schedule = !scheduled; scheduled = true; lock.unlock()
        guard schedule else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock(); let next = self.pending; self.pending = nil; self.scheduled = false; self.lock.unlock()
            guard self.window != nil, let next = next else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            self.imageLayer.contents = next
            CATransaction.commit()
            self.framesShown += 1
        }
    }

    // The raw monitor is only a canvas: keep the pointer on the virtual desktop.
    private func keepPointerOut() {
        guard virtual != nil, let location = CGEvent(source: nil)?.location else { return }
        let monitor = CGDisplayBounds(physical)
        guard monitor.contains(location) else { return }
        let desktop = CGDisplayBounds(virtualID).insetBy(dx: 1, dy: 1)
        let target = CGPoint(x: min(max(location.x, desktop.minX), desktop.maxX), y: min(max(location.y, desktop.minY), desktop.maxY))
        CGWarpMouseCursorPosition(target); CGAssociateMouseAndMouseCursorPosition(1)
    }
    @objc private func screensChanged() {
        guard virtual != nil else { return }
        if !CorrectionDisplays.isOnline(physical) { stop(reason: "El monitor se ha desconectado; corrección detenida."); return }
        if !CorrectionDisplays.isOnline(virtualID) { stop(reason: "macOS retiró el escritorio virtual; corrección detenida."); return }
        reassertWindow()
    }

    // ⌃⌥⌘D stops the correction from anywhere (no permission needed).
    private func installHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            guard let data = data else { return noErr }
            let engine = Unmanaged<CorrectionEngine>.fromOpaque(data).takeUnretainedValue()
            DispatchQueue.main.async { engine.stop() }
            return noErr
        }, 1, &spec, me, &hotKeyHandler)
        let id = EventHotKeyID(signature: OSType(0x50524453), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }
    private func removeHotKey() {
        if let hotKey = hotKey { UnregisterEventHotKey(hotKey) }; hotKey = nil
        if let handler = hotKeyHandler { RemoveEventHandler(handler) }; hotKeyHandler = nil
    }
    static func waitAsync(seconds: Double, until condition: @escaping () -> Bool, then done: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(seconds)
        func poll() {
            if condition() { done(true); return }
            if Date() > deadline { done(false); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: poll)
        }
        poll()
    }
    static func wait(seconds: Double, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > deadline { return false }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return true
    }
}

// "Corregir monitor" page. Every control drives the live compositor.
@available(macOS 12.3, *)
final class CorrectionPage: NSObject {
    let view: NSView
    let engine = CorrectionEngine()
    private let root = PrisonStack()
    private let monitorPopup = NSPopUpButton()
    private let desktopPopup = NSPopUpButton()
    private let aspectPopup = NSPopUpButton()
    private let startButton = NSButton(title: "Empezar corrección", target: nil, action: nil)
    private let fitButton = NSButton(title: "Centrar y ajustar", target: nil, action: nil)
    private let resetMarginsButton = NSButton(title: "Quitar márgenes", target: nil, action: nil)
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var sliders: [String: (NSSlider, NSTextField)] = [:]
    private var monitors: [CGDirectDisplayID] = []
    private var settings = CorrectionSettings()

    override init() {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        view = scroll
        super.init()
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 12, left: 24, bottom: 24, right: 24); root.translatesAutoresizingMaskIntoConstraints = false
        let document = PrisonSidebarDocument(); document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document; document.addSubview(root)
        let fill = root.widthAnchor.constraint(equalTo: document.widthAnchor); fill.priority = .defaultHigh
        NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor), root.centerXAnchor.constraint(equalTo: document.centerXAnchor), root.topAnchor.constraint(equalTo: document.topAnchor), root.bottomAnchor.constraint(equalTo: document.bottomAnchor), root.widthAnchor.constraint(lessThanOrEqualTo: document.widthAnchor), root.widthAnchor.constraint(lessThanOrEqualToConstant: 920), fill])

        let first = card("1 · MONITOR Y ESCRITORIO")
        text("El monitor sigue recibiendo su propia resolución. Dentro se dibuja el escritorio del Mac con su proporción, con bordes negros donde sobre. La pantalla del Mac no cambia: desde aquí puedes detenerlo siempre, o con ⌃⌥⌘D.", in: first)
        monitorPopup.target = self; monitorPopup.action = #selector(chooseMonitor)
        row("Monitor", monitorPopup, in: first)
        for (w, h) in CorrectionSettings.desktopSizes {
            let ratio = w * 9 == h * 16 ? "16:9" : "16:10"
            desktopPopup.addItem(withTitle: "\(w) × \(h) · \(ratio)")
        }
        desktopPopup.target = self; desktopPopup.action = #selector(chooseDesktop)
        row("Escritorio", desktopPopup, in: first)
        for (name, _) in CorrectionSettings.screenAspects { aspectPopup.addItem(withTitle: name) }
        aspectPopup.target = self; aspectPopup.action = #selector(chooseAspect)
        row("Forma de la pantalla", aspectPopup, in: first)
        text("Si la imagen se ve ensanchada o aplastada, elige aquí la forma real de la TV: el escritorio se corrige para verse con su proporción.", in: first)
        let buttons = NSStackView(); buttons.orientation = .horizontal; buttons.spacing = 10
        for (button, action) in [(startButton, #selector(toggle)), (fitButton, #selector(centerAndFit)), (resetMarginsButton, #selector(resetMargins))] {
            button.bezelStyle = .rounded; button.target = self; button.action = action; buttons.addArrangedSubview(button)
        }
        first.addArrangedSubview(buttons)
        statusLabel.font = .systemFont(ofSize: 12); statusLabel.textColor = NSColor(calibratedWhite: 0.7, alpha: 1)
        first.addArrangedSubview(statusLabel); statusLabel.widthAnchor.constraint(equalTo: first.widthAnchor).isActive = true

        let size = card("2 · TAMAÑO Y POSICIÓN")
        slider("scale", "Escala", 30, 150, unit: " %", in: size)
        slider("width", "Anchura (solo ancho)", CorrectionSettings.widthRange.lowerBound, CorrectionSettings.widthRange.upperBound, unit: " %", in: size)
        slider("offsetX", "Mover horizontal", -640, 640, unit: " px", in: size)
        slider("offsetY", "Mover vertical", -512, 512, unit: " px", in: size)
        let margins = card("3 · MÁRGENES (para la parte que la TV recorta)")
        slider("left", "Izquierdo", 0, 400, unit: " px", in: margins)
        slider("right", "Derecho", 0, 400, unit: " px", in: margins)
        slider("top", "Superior", 0, 400, unit: " px", in: margins)
        slider("bottom", "Inferior", 0, 400, unit: " px", in: margins)
        engine.onStopped = { [weak self] reason in self?.refresh(reason) }
        engine.onRestarted = { [weak self] in self?.refresh("Tamaño del escritorio cambiado.") }
        reload()
    }

    // Called when the page is shown and when screens change.
    func reload() {
        monitors = CorrectionDisplays.candidates()
        if engine.active, !monitors.contains(engine.physical) { monitors.insert(engine.physical, at: 0) }
        monitorPopup.removeAllItems()
        for id in monitors { monitorPopup.addItem(withTitle: "\(CorrectionDisplays.name(id)) · \(CorrectionDisplays.modeText(id))") }
        if monitors.isEmpty { monitorPopup.addItem(withTitle: "No hay monitor externo ampliado") }
        if engine.active, let index = monitors.firstIndex(of: engine.physical) { monitorPopup.selectItem(at: index) }
        chooseMonitor()
    }
    private var selected: CGDirectDisplayID? { monitors.indices.contains(monitorPopup.indexOfSelectedItem) ? monitors[monitorPopup.indexOfSelectedItem] : nil }
    @objc private func chooseMonitor() {
        if let id = selected, !(engine.active && engine.physical != id) { settings = engine.active ? engine.settings : CorrectionStore.load(id) }
        showSettings(); refresh(nil)
    }
    @objc private func chooseDesktop() {
        let (w, h) = CorrectionSettings.desktopSizes[max(0, desktopPopup.indexOfSelectedItem)]
        settings.desktopWidth = w; settings.desktopHeight = h; changed()
    }
    @objc private func chooseAspect() {
        settings.screenAspect = CorrectionSettings.screenAspects[max(0, aspectPopup.indexOfSelectedItem)].1; changed()
    }
    @objc private func toggle() {
        guard !engine.restarting else { return }
        if engine.active { engine.stop(); return }
        guard let id = selected else { refresh("Conecta el monitor como pantalla ampliada."); return }
        startButton.isEnabled = false; statusLabel.stringValue = "Preparando el escritorio corregido…"
        DispatchQueue.main.async {
            let error = self.engine.start(display: id, settings: self.settings)
            self.startButton.isEnabled = true
            self.refresh(error)
        }
    }
    @objc private func centerAndFit() { settings.centerAndFit(); showSettings(); changed() }
    @objc private func resetMargins() { settings.left = 0; settings.right = 0; settings.top = 0; settings.bottom = 0; showSettings(); changed() }
    @objc private func sliderMoved(_ slider: NSSlider) {
        guard let key = sliders.first(where: { $0.value.0 === slider })?.key else { return }
        let value = slider.doubleValue.rounded()
        switch key {
        case "scale": settings.scale = value / 100
        case "width": settings.width = value == 100 ? nil : value
        case "offsetX": settings.offsetX = value
        case "offsetY": settings.offsetY = value
        case "left": settings.left = value
        case "right": settings.right = value
        case "top": settings.top = value
        default: settings.bottom = value
        }
        sliders[key]?.1.stringValue = label(key, value)
        changed()
    }
    private func changed() {
        if let id = selected { CorrectionStore.save(settings, for: id) }
        if engine.active, !engine.restarting { engine.update(settings) }
        refresh(nil)
    }
    private func showSettings() {
        let values: [String: Double] = ["scale": settings.scale * 100, "width": settings.width ?? 100, "offsetX": settings.offsetX, "offsetY": settings.offsetY, "left": settings.left, "right": settings.right, "top": settings.top, "bottom": settings.bottom]
        for (key, value) in values { sliders[key]?.0.doubleValue = value; sliders[key]?.1.stringValue = label(key, value) }
        if let index = CorrectionSettings.desktopSizes.firstIndex(where: { $0.0 == settings.desktopWidth && $0.1 == settings.desktopHeight }) { desktopPopup.selectItem(at: index) }
        let automatic = selected.flatMap { CorrectionDisplays.physicalAspect($0) }
        aspectPopup.item(at: 0)?.title = "Automática · " + CorrectionDisplays.aspectName(automatic)
        aspectPopup.selectItem(at: CorrectionSettings.screenAspects.firstIndex(where: { $0.1 == settings.screenAspect }) ?? 0)
    }
    private func label(_ key: String, _ value: Double) -> String { key == "scale" || key == "width" ? "\(Int(value)) %" : "\(Int(value)) px" }
    private func refresh(_ message: String?) {
        startButton.title = engine.active ? "Detener corrección" : "Empezar corrección"
        monitorPopup.isEnabled = !engine.active
        var lines: [String] = []
        if let message = message { lines.append(message) }
        if let id = selected ?? (engine.active ? engine.physical : nil) {
            let frame = CGDisplayBounds(id).size
            let rect = engine.active ? engine.imageRect : CorrectionSettings.layout(frame: frame, desktop: CGSize(width: settings.desktopWidth, height: settings.desktopHeight), settings: settings, physicalAspect: CorrectionDisplays.physicalAspect(id))
            lines.append("Salida al monitor: \(CorrectionDisplays.modeText(id)).")
            lines.append("Imagen: \(Int(rect.width)) × \(Int(rect.height)) en x \(Int(rect.minX)), y \(Int(rect.minY)) · bordes: arriba \(Int(rect.minY)), abajo \(Int(frame.height - rect.maxY)), izquierda \(Int(rect.minX)), derecha \(Int(frame.width - rect.maxX)) px.")
        }
        if engine.active {
            lines.append("Activo. Mueve el ratón hacia el monitor para usar ese escritorio.")
            if !engine.note.isEmpty { lines.append(engine.note) }
        }
        statusLabel.stringValue = lines.joined(separator: "\n")
    }

    private func slider(_ key: String, _ title: String, _ min: Double, _ max: Double, unit: String, in stack: NSStackView) {
        let slider = NSSlider(value: 0, minValue: min, maxValue: max, target: self, action: #selector(sliderMoved(_:)))
        slider.isContinuous = true; slider.setAccessibilityLabel(title)
        let value = NSTextField(labelWithString: "")
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); value.textColor = NSColor(calibratedWhite: 0.75, alpha: 1); value.alignment = .right
        value.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let row = NSStackView(); row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 12
        let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 13, weight: .medium); label.textColor = .white
        label.widthAnchor.constraint(equalToConstant: 150).isActive = true
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for view in [label, slider, value] { row.addArrangedSubview(view) }
        stack.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        sliders[key] = (slider, value)
    }
    private func row(_ title: String, _ control: NSView, in stack: NSStackView) {
        let row = NSStackView(); row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 12
        let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 13, weight: .medium); label.textColor = .white
        label.widthAnchor.constraint(equalToConstant: 150).isActive = true
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(label); row.addArrangedSubview(control)
        stack.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func card(_ title: String) -> NSStackView {
        let box = NSView(); box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(calibratedRed: 0.105, green: 0.115, blue: 0.14, alpha: 1).cgColor
        box.layer?.borderColor = NSColor(calibratedRed: 0.19, green: 0.20, blue: 0.23, alpha: 1).cgColor
        box.layer?.borderWidth = 1; box.layer?.cornerRadius = 12; box.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(box)
        box.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -(root.edgeInsets.left + root.edgeInsets.right)).isActive = true
        let inner = PrisonStack(); inner.orientation = .vertical; inner.alignment = .leading; inner.spacing = 10
        inner.translatesAutoresizingMaskIntoConstraints = false; box.addSubview(inner)
        NSLayoutConstraint.activate([inner.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 18), inner.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -18), inner.topAnchor.constraint(equalTo: box.topAnchor, constant: 18), inner.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -18)])
        let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 11, weight: .semibold); label.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        inner.addArrangedSubview(label)
        return inner
    }
    private func text(_ string: String, in stack: NSStackView) {
        let label = NSTextField(wrappingLabelWithString: string); label.font = .systemFont(ofSize: 13); label.textColor = NSColor(calibratedWhite: 0.65, alpha: 1)
        stack.addArrangedSubview(label); label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
}
#endif
