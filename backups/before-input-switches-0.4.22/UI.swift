import AppKit
import AVFoundation
#if !LEGACY
import Network
#endif
import CoreMedia
import os.log


// A connection is green only after image delivery, never merely after TCP/TLS.
enum StreamPhase: Equatable {
    case idle, available, connecting, preparing, streaming, applying, reconnecting, failed
    var title: String {
        switch self {
        case .idle: return "Sin conexión"
        case .available: return "Disponible para conectar"
        case .connecting: return "Conectando con el otro Mac…"
        case .preparing: return "Conectado · esperando la primera imagen"
        case .streaming: return "Imagen en directo"
        case .applying: return "Aplicando cambios de pantalla…"
        case .reconnecting: return "Conexión interrumpida · reconectando"
        case .failed: return "Necesita atención"
        }
    }
    var color: NSColor {
        switch self {
        case .streaming: return .systemGreen
        case .failed: return .systemRed
        case .connecting, .preparing, .applying, .reconnecting: return .systemOrange
        default: return prisonSecondaryText
        }
    }
}

final class PrisonDocument: NSView { override var isFlipped: Bool { true } }

final class PrisonStack: NSStackView { override var isFlipped: Bool { true } }

func prisonMonoFont(_ size: CGFloat) -> NSFont { NSFont(name: "Menlo", size: size) ?? .systemFont(ofSize: size) }
let prisonAccent = NSColor(calibratedRed: 0.52, green: 0.40, blue: 1, alpha: 1)
let prisonSecondaryText = NSColor(calibratedWhite: 0.74, alpha: 1)
var virtualDisplaySupported: Bool {
    ["CGVirtualDisplay", "CGVirtualDisplayDescriptor", "CGVirtualDisplayMode", "CGVirtualDisplaySettings"].allSatisfy { NSClassFromString($0) != nil }
}
// Draw inside the control bounds even when a device name or translation is long.
func prisonButtonTitle(_ title: String, bounds: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .center) {
    NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
    NSBezierPath(rect: bounds).addClip()
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = alignment; paragraph.lineBreakMode = .byTruncatingTail
    let area = bounds.insetBy(dx: 12, dy: 0)
    (title as NSString).draw(in: NSRect(x: area.minX, y: bounds.midY-font.ascender/2-2, width: max(0, area.width), height: ceil(font.ascender-font.descender)+3), withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
}
final class PrisonActionButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        let color = isEnabled ? prisonAccent : NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.20, alpha: 1)
        (cell?.isHighlighted == true ? color.blended(withFraction: 0.2, of: .black)! : color).setFill()
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
        if isEnabled { NSGradient(starting: color, ending: color.blended(withFraction: 0.13, of: .white)!)?.draw(in: shape, angle: 80) } else { shape.fill() }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white]
        prisonButtonTitle(title, bounds: bounds, font: attributes[.font] as! NSFont, color: attributes[.foregroundColor] as! NSColor)
    }
}

final class PrisonSecondaryButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        let base = NSColor(calibratedWhite: isEnabled ? 0.17 : 0.11, alpha: 1)
        (cell?.isHighlighted == true ? base.blended(withFraction: 0.18, of: .white)! : base).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: isEnabled ? NSColor.white : NSColor.disabledControlTextColor]
        prisonButtonTitle(title, bounds: bounds, font: attributes[.font] as! NSFont, color: attributes[.foregroundColor] as! NSColor)
    }
}

final class PrisonPopUpButton: NSPopUpButton {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
    override func draw(_ dirtyRect: NSRect) {
        let base = NSColor(calibratedWhite: isEnabled ? 0.16 : 0.10, alpha: 1)
        base.setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).fill()
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: isEnabled ? NSColor.white : prisonSecondaryText, .paragraphStyle: paragraph]
        (title as NSString).draw(in: NSRect(x: 12, y: (bounds.height-18)/2, width: max(0, bounds.width-42), height: 20), withAttributes: attributes)
        prisonSecondaryText.setStroke()
        let arrow = NSBezierPath(); arrow.lineWidth = 1.5
        arrow.move(to: NSPoint(x: bounds.width-23, y: bounds.midY+2)); arrow.line(to: NSPoint(x: bounds.width-19, y: bounds.midY-2)); arrow.line(to: NSPoint(x: bounds.width-15, y: bounds.midY+2)); arrow.stroke()
    }
}

// Native vector illustration: scales with the window on High Sierra and later.
final class PrisonStatusPill: NSTextField {
    override func draw(_ dirtyRect: NSRect) {
        prisonButtonTitle(stringValue, bounds: bounds, font: font ?? .systemFont(ofSize: 11), color: textColor ?? .white)
    }
}
final class PrisonConnectionOverview: NSView {
    var localName = Host.current().localizedName ?? "Este Mac" { didSet { if oldValue != localName { needsDisplay = true } } }
    var remoteName = "Otra pantalla" { didSet { if oldValue != remoteName { needsDisplay = true } } }
    var live = false { didSet { if oldValue != live { needsDisplay = true } } }
    override var intrinsicContentSize: NSSize { NSSize(width: 400, height: 178) }
    private func label(_ value: String, at center: CGFloat, y: CGFloat, width: CGFloat, bold: Bool) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
        (value as NSString).draw(in: NSRect(x: center-width/2, y: y, width: width, height: 20), withAttributes: [.font: NSFont.systemFont(ofSize: bold ? 13 : 11, weight: bold ? .semibold : .regular), .foregroundColor: bold ? NSColor.white : prisonSecondaryText, .paragraphStyle: paragraph])
    }
    private func device(center: CGFloat, width: CGFloat, laptop: Bool) {
        let height = width * 0.61
        let screen = NSRect(x: center-width/2, y: 62, width: width, height: height)
        let frame = NSBezierPath(roundedRect: screen.insetBy(dx: -4, dy: -4), xRadius: 5, yRadius: 5)
        NSColor(calibratedWhite: 0.045, alpha: 1).setFill(); frame.fill()
        NSColor(calibratedWhite: 0.58, alpha: 1).setStroke(); frame.lineWidth = 1; frame.stroke()
        NSGradient(starting: NSColor(calibratedRed: 0.29, green: 0.22, blue: 0.58, alpha: 1), ending: NSColor(calibratedRed: 0.09, green: 0.07, blue: 0.22, alpha: 1))?.draw(in: screen, angle: -50)
        let wave = NSBezierPath(); wave.move(to: NSPoint(x: screen.minX, y: screen.maxY*0.85))
        wave.curve(to: NSPoint(x: screen.maxX, y: screen.minY+height*0.28), controlPoint1: NSPoint(x: center, y: screen.maxY), controlPoint2: NSPoint(x: center, y: screen.minY))
        wave.line(to: NSPoint(x: screen.maxX, y: screen.minY)); wave.line(to: screen.origin); wave.close()
        NSColor(calibratedRed: 0.12, green: 0.09, blue: 0.31, alpha: 0.7).setFill(); wave.fill()
        let metal = NSColor(calibratedWhite: 0.63, alpha: 1); metal.setFill()
        if laptop {
            NSBezierPath(roundedRect: NSRect(x: center-width*0.63, y: 53, width: width*1.26, height: 5), xRadius: 2, yRadius: 2).fill()
        } else {
            NSBezierPath(rect: NSRect(x: center-width/2-4, y: 52, width: width+8, height: 9)).fill()
            NSBezierPath(rect: NSRect(x: center-7, y: 39, width: 14, height: 14)).fill()
            NSBezierPath(roundedRect: NSRect(x: center-23, y: 36, width: 46, height: 4), xRadius: 2, yRadius: 2).fill()
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        let left = bounds.width*0.25, right = bounds.width*0.75
        let width = min(150, bounds.width*0.28)
        let start = left+width*0.65, end = right-width*0.65
        (live ? prisonAccent : NSColor(calibratedWhite: 0.37, alpha: 1)).setFill()
        if end > start { for x in stride(from: start, through: end, by: 12) { NSBezierPath(ovalIn: NSRect(x: x, y: 98, width: 4, height: 4)).fill() } }
        device(center: left, width: width*0.85, laptop: true); device(center: right, width: width, laptop: false)
        label("Este Mac", at: left, y: 20, width: bounds.width*0.44, bold: true)
        label(localName, at: left, y: 2, width: bounds.width*0.44, bold: false)
        label(remoteName, at: right, y: 16, width: bounds.width*0.44, bold: true)
    }
}

final class PrisonHeader: NSView {
    private let logo = Bundle.main.url(forResource: "PrisonLogo", withExtension: "jpg").flatMap { NSImage(contentsOf: $0) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        if let logo = logo {
            let width = min(bounds.width - 48, 390, (bounds.height-48)*850/185)
            logo.draw(in: NSRect(x: (bounds.width-width)/2, y: bounds.height - width*185/850 - 10, width: width, height: width*185/850), from: NSRect(x: 55, y: 105, width: 850, height: 185), operation: .sourceOver, fraction: 1)
        }
        let text = "DISPLAY" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white, .kern: 7]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width-size.width)/2, y: 15), withAttributes: attributes)
    }
}

final class VideoView: NSView {
    let videoLayer = AVSampleBufferDisplayLayer()
    let badge = NSTextField(labelWithString: "PRISON DISPLAY · v\(AppVersion.current)")
    let connectionStatus = NSTextField(wrappingLabelWithString: "Conectando con el otro Mac…")
    var keyboardEnabled = false { didSet { if !keyboardEnabled { releaseKeyboard() } } }
    var onKeyboard: ((KeyboardMessage) -> Void)?
    private var keyboardFocused = false
    var desktopControlActive = false { didSet { layoutCursor() } }
    var cursorInVideo = false { didSet { window?.invalidateCursorRects(for: self); layoutCursor() } }
    private let emptyCursor = NSCursor(image: NSImage(size: NSSize(width: 1, height: 1)), hotSpot: .zero)
    private var hasImage = false
    private var imageSize = CGSize.zero
    private var imageFormat: CMVideoFormatDescription?
    private let cursorLayer = CALayer()
    private var cursorPosition: CGPoint?
    private var cursorVisible = false
    private var localInputUntil: UInt64 = 0
    private var heldLeft = false
    private var heldRight = false
    private var lastPointer = CGPoint(x: 0.5, y: 0.5)
    func releaseLocalButtons() {
        if heldLeft { onPointer?(PointerMessage(action: .leftUp, x: Double(lastPointer.x), y: Double(lastPointer.y))) }
        if heldRight { onPointer?(PointerMessage(action: .rightUp, x: Double(lastPointer.x), y: Double(lastPointer.y))) }
        heldLeft = false; heldRight = false
    }
    private var tracking: NSTrackingArea?
    var onPointer: ((PointerMessage) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    private var imageRect: CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let horizontal = bounds.width / imageSize.width, vertical = bounds.height / imageSize.height
        let scale = videoLayer.videoGravity == .resizeAspectFill ? max(horizontal, vertical) : min(horizontal, vertical)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2, width: size.width, height: size.height)
    }
    override func updateTrackingAreas() {
        if let tracking = tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(next); tracking = next; super.updateTrackingAreas()
        window?.acceptsMouseMovedEvents = true
    }
    override func resetCursorRects() { addCursorRect(imageRect.intersection(bounds), cursor: cursorInVideo ? emptyCursor : .arrow) }
    func setFullscreenPresentation(_ fullscreen: Bool) {
        releaseLocalButtons()
        videoLayer.videoGravity = fullscreen ? .resizeAspectFill : .resizeAspect
        window?.invalidateCursorRects(for: self)
        layoutCursor()
    }
    func releaseKeyboard() { if keyboardFocused { onKeyboard?(KeyboardMessage(action: .releaseAll)) }; keyboardFocused = false }
    func forwardKey(_ event: NSEvent, action: KeyboardMessage.Action) -> Bool {
        guard keyboardEnabled, keyboardFocused, hasImage, window?.isKeyWindow == true, window?.firstResponder === self else { return false }
        if event.modifierFlags.contains(.command), [12, 4, 48].contains(event.keyCode) { return false }
        if event.keyCode == 53, window?.styleMask.contains(.fullScreen) == true { window?.toggleFullScreen(nil); releaseKeyboard(); return true }
        onKeyboard?(KeyboardMessage(action: action, keyCode: event.keyCode, flags: UInt64(event.modifierFlags.rawValue), repeated: action == .down && event.isARepeat)); return true
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, forwardKey(event, action: .down) { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) { if !forwardKey(event, action: .down) { super.keyDown(with: event) } }
    override func keyUp(with event: NSEvent) { if !forwardKey(event, action: .up) { super.keyUp(with: event) } }
    override func flagsChanged(with event: NSEvent) { if !forwardKey(event, action: .modifiers) { super.flagsChanged(with: event) } }
    func remoteCursor(x: Double, y: Double, visible: Bool) {
        cursorPosition = CGPoint(x: x, y: y); cursorVisible = visible; layoutCursor()
    }
    private func layoutCursor() {
        // A remote pointer does not require a WindowServer mouse query. Only
        // check the local position while suppressing a recent local-input echo.
        let suppressLocalEcho = window?.isKeyWindow == true && monotonicNS() < localInputUntil
        let local = suppressLocalEcho ? window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) } : nil
        let localInside = local.flatMap { PointerMessage.normalized($0, in: imageRect.intersection(bounds)) } != nil
        // Keep the received cursor overlay visible during desktop crossing.
        // The OS may accept injected movement while its native cursor is not
        // rendered in this receiver's video window; suppressing the overlay
        // here made input work with no visible pointer.
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        cursorLayer.isHidden = cursorInVideo || !hasImage || !cursorVisible || (suppressLocalEcho && localInside)
        guard let position = cursorPosition else { return }
        let r = imageRect
        cursorLayer.frame = CGRect(x: r.minX + position.x*r.width, y: r.maxY - position.y*r.height - 24, width: 24, height: 24)
    }
    private func sendPointer(_ event: NSEvent, action: PointerMessage.Action) {
        guard hasImage else { return }
        let r = imageRect, visibleRect = r.intersection(bounds)
        guard !visibleRect.isEmpty else { return }
        var point = convert(event.locationInWindow, from: nil)
        let release = action == .leftUp || action == .rightUp
        if release { point.x = min(max(point.x, visibleRect.minX), visibleRect.maxX-0.001); point.y = min(max(point.y, visibleRect.minY), visibleRect.maxY-0.001) }
        guard visibleRect.contains(point) else { return }
        guard let normalized = PointerMessage.normalized(point, in: r) else { return }
        lastPointer = CGPoint(x: normalized.x, y: 1-normalized.y)
        localInputUntil = monotonicNS() + 500_000_000
        if action == .leftDown { heldLeft = true }; if action == .leftUp { heldLeft = false }
        if action == .rightDown { heldRight = true }; if action == .rightUp { heldRight = false }
        onPointer?(PointerMessage(action: action, x: Double(normalized.x), y: Double(1-normalized.y), delta: action == .scroll ? max(-120, min(120, event.scrollingDeltaY)) : 0, clicks: (action == .leftDown || action == .rightDown || action == .leftUp || action == .rightUp) ? max(1, min(3, event.clickCount)) : 1, deltaX: action == .scroll ? max(-120, min(120, event.scrollingDeltaX)) : 0, flags: UInt64(event.modifierFlags.rawValue)))
        layoutCursor()
    }
    override func mouseMoved(with event: NSEvent) { sendPointer(event, action: .move) }
    override func mouseDragged(with event: NSEvent) { sendPointer(event, action: .move) }
    override func rightMouseDragged(with event: NSEvent) { sendPointer(event, action: .move) }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); keyboardFocused = hasImage && imageRect.intersection(bounds).contains(convert(event.locationInWindow, from: nil)); sendPointer(event, action: .leftDown) }
    override func mouseUp(with event: NSEvent) { sendPointer(event, action: .leftUp) }
    override func rightMouseDown(with event: NSEvent) { window?.makeFirstResponder(self); keyboardFocused = hasImage && imageRect.intersection(bounds).contains(convert(event.locationInWindow, from: nil)); sendPointer(event, action: .rightDown) }
    override func rightMouseUp(with event: NSEvent) { sendPointer(event, action: .rightUp) }
    override func scrollWheel(with event: NSEvent) { sendPointer(event, action: .scroll) }
    override func mouseExited(with event: NSEvent) { layoutCursor() }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect); wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor; layer?.masksToBounds = true
        videoLayer.videoGravity = .resizeAspect; layer?.addSublayer(videoLayer)
        // Render a concrete cursor bitmap: older AppKit template cursor images
        // can become transparent when used as CALayer contents on High Sierra.
        cursorLayer.contents = Self.cursorBitmap(); cursorLayer.contentsScale = 2
        cursorLayer.contentsGravity = .resizeAspect; cursorLayer.zPosition = 100
        cursorLayer.isHidden = true; layer?.addSublayer(cursorLayer)
        badge.textColor = NSColor(calibratedWhite: 0.82, alpha: 1); badge.font = .systemFont(ofSize: 10, weight: .medium)
        badge.drawsBackground = true; badge.backgroundColor = NSColor.black.withAlphaComponent(0.45)
        addSubview(badge)
        connectionStatus.textColor = .white; connectionStatus.alignment = .center
        connectionStatus.font = .systemFont(ofSize: 17, weight: .medium)
        addSubview(connectionStatus)
    }
    private static func cursorBitmap() -> CGImage? {
        guard let context = CGContext(data: nil, width: 48, height: 48, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: 2, y: 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 2, y: 22))
        for point in [CGPoint(x: 2, y: 3), CGPoint(x: 7, y: 8), CGPoint(x: 11, y: 1), CGPoint(x: 15, y: 3), CGPoint(x: 11, y: 10), CGPoint(x: 19, y: 10)] { path.addLine(to: point) }
        path.closeSubpath(); context.addPath(path)
        context.setFillColor(NSColor.white.cgColor); context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1.5); context.setLineJoin(.round); context.drawPath(using: .fillStroke)
        return context.makeImage()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); layoutCursor(); CATransaction.begin(); CATransaction.setDisableActions(true); videoLayer.frame = bounds; CATransaction.commit(); badge.frame = NSRect(x: 12, y: 12, width: 280, height: 22); connectionStatus.frame = NSRect(x: 30, y: max(45, bounds.midY - 45), width: max(0, bounds.width - 60), height: 90) }
    func updateStatus(_ text: String) { connectionStatus.stringValue = text; connectionStatus.isHidden = hasImage }
    @discardableResult func present(_ pixel: CVPixelBuffer) throws -> Bool {
        imageSize = CGSize(width: CVPixelBufferGetWidth(pixel), height: CVPixelBufferGetHeight(pixel))
        // Reuse only when CoreMedia confirms dimensions, pixel format and
        // image attachments still match. Resolution or colour changes rebuild it.
        if imageFormat.map({ CMVideoFormatDescriptionMatchesImageBuffer($0, imageBuffer: pixel) }) != true {
            var format: CMVideoFormatDescription?
            guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixel, formatDescriptionOut: &format) == noErr, let format = format else { throw AireError("No se pudo mostrar el fotograma.") }
            imageFormat = format
        }
        guard let f = imageFormat else { throw AireError("Formato de imagen no disponible.") }
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixel, formatDescription: f, sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let s = sample else { throw AireError("No se pudo preparar la imagen.") }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(s, createIfNecessary: true) as? [NSMutableDictionary] { attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] = true }
        if videoLayer.status == .failed { videoLayer.flush() }
        guard videoLayer.isReadyForMoreMediaData else { backpressureFrames += 1; return false }
        videoLayer.enqueue(s)
        acceptedFrames += 1
        hasImage = true; connectionStatus.isHidden = true; layoutCursor(); return true
    }
    func clear() { releaseKeyboard(); cursorInVideo = false; videoLayer.flushAndRemoveImage(); hasImage = false; connectionStatus.isHidden = false; cursorLayer.isHidden = true; imageSize = .zero; imageFormat = nil }
    private(set) var acceptedFrames = 0
    private(set) var backpressureFrames = 0
}

final class PrisonViewerWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Keep application exit/hide and macOS app switching local.
        if ![12, 4, 48].contains(event.keyCode), firstResponder === contentView,
           let view = contentView as? VideoView, view.forwardKey(event, action: .down) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

#if SENDER || UNIFIED
struct StreamOptions: Equatable {
    let extend: Bool; let width: Int; let height: Int; let fps: Int; let bitrate: Int; var nativeCursor = false
    // At 60 FPS a QP cap of 32 forced RTVC to omit most scrolling desktop
    // images. Keep a bounded text-quality cap while allowing continuous motion.
    var maxFrameQP: Int? { bitrate >= 20_000_000 ? (fps >= 50 ? 36 : 32) : nil }
    func sameCapture(as other: StreamOptions) -> Bool {
        extend == other.extend && width == other.width && height == other.height && fps == other.fps && nativeCursor == other.nativeCursor
    }
}
final class SenderEngine {
    // Brightness uses the existing authenticated connection, never a public service.
    var onBrightnessPacket: ((Wire.Kind, Data) -> Void)?
    func sendBrightness(_ kind: Wire.Kind, _ data: Data) {
        guard kind == .brightnessCommand || kind == .brightnessResult, data.count <= 1024 else { return }
        queue.async { [weak self] in
            guard let self = self, self.authenticated else { return }
            self.peer?.send(kind, data)
        }
    }
    func requestFullscreen() {
        queue.async { [weak self] in
            guard let self = self, self.authenticated, self.phase == .streaming else { return }
            self.peer?.send(.fullscreenCommand)
        }
    }

    var screenSlot = 0
    var discoveryLabel: String?
    let queue = DispatchQueue(label: "AireDisplay.sender", qos: .userInteractive)
    var onStatus: ((String) -> Void)?
    var onPhase: ((StreamPhase) -> Void)?
    var onPeerConnected: ((String) -> Void)?
    private(set) var phase = StreamPhase.idle
    private func setPhase(_ value: StreamPhase) {
        guard phase != value else { return }; phase = value; onPhase?(value)
    }
    var onSessionActive: (() -> Void)?
    var onMetrics: ((String) -> Void)?
    var onFirstImage: (() -> Void)?
    private var imageConfirmed = false
    private var captureSequenceFloor: UInt64 = 0
    private var presentedSequence: UInt64 = 0
    private func confirmPresentedImage() {
        guard !imageConfirmed, !adjusting, !rebuilding, presentedSequence > captureSequenceFloor, let options = appliedOptions else { return }
        imageConfirmed = true; setPhase(.streaming)
        onStatus?(options.extend ? "Escritorio extendido activo. El otro Mac está mostrando la imagen." : "Pantalla duplicada. El otro Mac está mostrando la imagen.")
        onFirstImage?()
    }
    var onFrameRoundTrip: ((Double) -> Void)?
    private var listener: NWListener?
    var onListenerPrepared: ((NWListener) -> Void)?
    private lazy var pairing = PairingServer(queue: queue)
    var onLink: ((ConnectionLink?) -> Void)?
    var onConfirm: ((String, String, @escaping (Bool) -> Void) -> Void)?
    private var peer: Peer?
    private var encoder: H264Encoder?
    private var capture: Capture?
    let pointer = PointerInjector()
    let keyboard = KeyboardInjector()
    var desktopPermission: () -> Bool = { AXIsProcessTrusted() }
    private let desktopOwner = UUID()
    private var desktopToken: UInt64?
    private var desktopExpiry: DispatchWorkItem?
    private func endDesktopControl() {
        desktopExpiry?.cancel(); desktopExpiry = nil; desktopToken = nil
        DesktopInputOwnership.shared.release(desktopOwner)
        pointer.releaseButtons(); keyboard.releaseKeys(); pointer.desktopDisplayID = nil
    }
    private func desktopControl(_ message: DesktopControlMessage, reply: @escaping (Wire.Kind, Data) -> Void) throws {
        guard [.begin, .end, .heartbeat].contains(message.action) else { throw AireError("Control de escritorio inesperado.") }
        if message.action == .end { if desktopToken == message.token { endDesktopControl() }; return }
        if message.action == .heartbeat, desktopToken != message.token {
            reply(.desktopControl, DesktopControlMessage(action: .rejected, token: message.token).serialize()); return
        }
        guard desktopPermission(), !adjusting, !rebuilding, pointer.displayID != 0 else {
            if desktopToken == message.token { endDesktopControl() }
            reply(.desktopControl, DesktopControlMessage(action: .rejected, token: message.token).serialize()); return
        }
        if message.action == .begin {
            endDesktopControl()
            guard DesktopInputOwnership.shared.acquire(desktopOwner) else {
                reply(.desktopControl, DesktopControlMessage(action: .rejected, token: message.token).serialize()); return
            }
            desktopToken = message.token; pointer.desktopDisplayID = CGMainDisplayID()
        }
        desktopExpiry?.cancel()
        let lease = DispatchWorkItem { [weak self] in
            guard let self = self, self.desktopToken == message.token else { return }
            self.endDesktopControl()
            reply(.desktopControl, DesktopControlMessage(action: .rejected, token: message.token).serialize())
        }
        desktopExpiry = lease; queue.asyncAfter(deadline: .now()+3, execute: lease)
        let b = DisplayGeometry.shared.bounds(CGMainDisplayID())
        reply(.desktopControl, DesktopControlMessage(action: .accepted, token: message.token, width: UInt32(b.width), height: UInt32(b.height)).serialize())
    }
    private func receiveInput(_ kind: Wire.Kind, _ data: Data, reply: @escaping (Wire.Kind, Data) -> Void) throws {
        if kind == .desktopControl { try desktopControl(DesktopControlMessage(data), reply: reply) }
        else if kind == .desktopPointer || kind == .desktopKeyboard {
            var reader = Reader(data); let token = try reader.u64(); let body = try reader.rest()
            if kind == .desktopPointer {
                let message = try PointerMessage(body)
                if desktopToken == token, !adjusting, !rebuilding { pointer.receive(message) }
            } else {
                let message = try KeyboardMessage(body)
                if desktopToken == token { keyboard.receive(message) }
            }
        } else if kind == .keyboard {
            let message = try KeyboardMessage(data)
            if desktopToken == nil, pointer.displayID != 0 { keyboard.receive(message) }
        } else if kind == .pointer {
            let message = try PointerMessage(data)
            if desktopToken == nil, !adjusting, !rebuilding { pointer.receive(message) }
        } else { throw AireError("Entrada inesperada.") }
    }
    var screenPermission: () -> Bool = { ScreenCaptureAccess.permitted() }
    private let cursorChannel = CursorChannel()
    let streamActivity = StreamActivity()
    private var inputDelivery: OrderedInputDelivery?
    // Cursor and input use a separate encrypted socket without video decoding.
    var dedicatedCursorEnabled = true
    private var fastInputUsed = false
    private var advertisedService: NWListener.Service?
    private var pairingConfiguration: (key: String, service: String)?
    var videoFlightLimit = 2
    var cursorLocation: () -> CGPoint = { CGEvent(source: nil)?.location ?? CGPoint(x: -100000, y: -100000) }
    private var virtual: ADVirtualScreen?
    // Display creation/retirement may wait on macOS. Keep it off both the UI
    // thread and the encrypted video/input queues, and serialize its lifetime.
    private let displayQueue = DispatchQueue(label: "PrisonDisplay.displays", qos: .userInitiated)
    var graphicsLoadReader: () -> Double? = GraphicsLoadMonitor.systemLoad
    private lazy var graphicsMonitor = GraphicsLoadMonitor(reader: { [weak self] in self?.graphicsLoadReader() })
    private var graphicsEpoch = UUID()
    private var active = false
    private var authenticated = false
    private var encoding = 0
    private var encoderWarmed = false
    private var encoderDrainRequested = false
    private var latest = LatestFrame<(CVPixelBuffer, UInt64)>()
    private var quality = AdaptiveQuality(ceiling: 12_000_000)
    private var window = VideoWindow()
    var compatibilityEncoderEnabled: Bool = {
        let system = ProcessInfo.processInfo.operatingSystemVersion
        return system.majorVersion == 10 && system.minorVersion == 13
    }()
    private var requestedOptions: StreamOptions?
    var onOptionsApplied: ((StreamOptions) -> Void)?
    private var appliedOptions: StreamOptions?
    private var adjusting = false
    private var rebuilding = false
    private var lastSequence: UInt64 = 0
    private var generation = UUID()
    private var frames = 0
    private var videoBytes = 0
    private var roundTripTotal = 0.0
    private var metricStart = monotonicNS()
    private var pendingCaptureStops = 0
    private var captureRecoveries: [UInt64] = []
    private var captureStopping: Bool { pendingCaptureStops > 0 }
    func start(key: String, options: StreamOptions, rememberedService: String? = nil) throws {
        guard screenPermission() else { throw AireError("Activa PRISON DISPLAY en Grabación de pantalla y del audio del sistema (bloque superior de Ajustes) y vuelve a abrir la app. Solo audio no permite compartir la pantalla.") }
        let p = try networkParameters(key: key)
        let listener = try NWListener(using: p, on: .any)
        let serviceName = rememberedService ?? ("AireDisplay-" + UUID().uuidString)
        listener.service = NWListener.Service(name: serviceName, type: Wire.service)
        
        queue.async {
            self.window = VideoWindow(limit: self.dedicatedCursorEnabled ? 1 : self.videoFlightLimit)
            self.captureRecoveries.removeAll()
            self.requestedOptions = options; self.appliedOptions = nil; self.adjusting = false; self.rebuilding = false; self.lastSequence = 0
            self.active = true; self.authenticated = false; self.generation = UUID(); self.listener = listener; self.setPhase(.connecting)
            self.advertisedService = listener.service; self.fastInputUsed = false
            self.pairingConfiguration = (key, serviceName)
            listener.stateUpdateHandler = { [weak self] state in
                guard let self = self, self.active, self.listener === listener else { return }
                if case .ready = state {
                    guard let port = listener.port?.rawValue else { return }
                    do {
                        self.pairing.onConfirm = self.onConfirm; self.pairing.onStatus = self.onStatus
                        // The authenticated stream hello supplies the peer name on every reconnect.
                        self.pairing.onPeerConnected = nil
                        self.pairing.onRequest = { [weak self] waiting in
                            guard let self = self, self.active, !self.authenticated else { return }
                            self.setPhase(waiting ? .connecting : .available)
                        }
                        try self.pairing.start(streamPort: port, streamKey: key, serviceName: serviceName, displayLabel: self.discoveryLabel)
                        let host = localConnectionHostname()
                        self.onLink?(try ConnectionLink(host: host, port: port, key: key, serviceName: serviceName))
                        self.setPhase(.available)
                        self.onStatus?("Disponible para conectar. En el otro Mac, elige Recibir pantalla y selecciona este equipo.")
                    } catch { self.stopOnQueue("\(error)") }
                }
                if case .failed(let error) = state { self.stopOnQueue("No se pudo escuchar: \(error)") }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self = self, self.active, self.listener === listener, self.peer == nil else { connection.cancel(); return }
                let peer = Peer(connection, queue: self.queue); self.peer = peer
                peer.onReady = { peer.send(.hello, Wire.hello(role: "sender")) }
                peer.onPacket = { [weak self, weak peer] kind, data in
                    guard let self = self, let peer = peer, self.peer === peer else { return }
                    do {
                        if kind == .hello {
                            guard !self.authenticated else { throw AireError("Saludo duplicado.") }
                            _ = try Wire.checkHello(data, expected: "receiver"); self.onPeerConnected?(try Wire.peerName(data)); self.authenticated = true; self.streamActivity.start(); self.pairing.stop()
                            self.listener?.service = nil
                            let session = self.generation
                            if self.dedicatedCursorEnabled {
                                self.cursorChannel.onReady = { [weak self] in self?.queue.async {
                                    guard let self = self, self.generation == session, self.authenticated else { return }
                                    self.window.setLimit(self.videoFlightLimit); self.encodeLatest()
                                } }
                                let delivery = OrderedInputDelivery(queue: self.queue, receive: { [weak self] kind, data in
                                    guard let self = self, self.generation == session, self.authenticated else { return }
                                    do {
                                        self.fastInputUsed = true
                                        try self.receiveInput(kind, data, reply: { [weak self] in self?.cursorChannel.sendInput($0, $1) })
                                    } catch { self.peer?.end("\(error)") }
                                }, overflow: { [weak self] in
                                    guard let self = self, self.generation == session, self.authenticated else { return }
                                    self.peer?.end("Demasiados eventos de entrada pendientes. Reconectando…")
                                })
                                self.inputDelivery = delivery
                                self.cursorChannel.onInput = { [weak delivery] in delivery?.submit($0, $1) }
                                self.cursorChannel.onUnavailable = { [weak self] _ in self?.queue.async {
                                    guard let self = self, self.generation == session else { return }
                                    if self.fastInputUsed || (self.encoder?.inputCapacity ?? 1) > 1 { self.peer?.end("El canal de ratón y teclado se interrumpió. Reconectando…") }
                                    else { self.window.setLimit(1) }
                                } }
                                try? self.cursorChannel.startServer(host: localConnectionHostname()) { [weak self] offer in self?.queue.async {
                                    guard let self = self, self.active, self.authenticated, self.generation == session else { return }
                                    self.peer?.send(.cursorOffer, offer.data)
                                } }
                            }
                            if !self.captureStopping { self.beginCapture(self.requestedOptions ?? options) }
                        } else if kind == .brightnessCommand || kind == .brightnessResult {
                            guard self.authenticated, data.count <= 1024 else { throw AireError("Ajuste de brillo no autorizado o inválido.") }
                            self.onBrightnessPacket?(kind, data)
                        } else if kind == .ack, self.authenticated {
                            var r = Reader(data); let seq = try r.u64(); let sent = try r.u64()
                            let decodedNS = try r.u64()
                            guard data.count == 24, sent <= monotonicNS() else { throw AireError("Confirmación de vídeo inválida.") }
                            let transportNS = try self.window.acknowledge(sequence: seq, timestamp: sent)
                            let roundTrip = Double(monotonicNS() - sent) / 1e6
                            self.onFrameRoundTrip?(roundTrip)
                            if let rate = self.quality.observe(roundTripMS: Double(transportNS)/1e6, now: monotonicNS()) { try self.encoder?.updateBitrate(rate) }
                            self.encodeLatest()
                            self.applyWhenDrained()
                            self.frames += 1; self.roundTripTotal += roundTrip
                            let now = monotonicNS(); let elapsed = Double(now - self.metricStart) / 1e9
                            if elapsed >= 1 {
                                let rtt = self.roundTripTotal / Double(self.frames)
                                self.onMetrics?(String(format: "%d × %d · %.0f FPS · ida/vuelta %.1f ms · decod. %.1f ms · vídeo %.1f Mb/s · objetivo %.1f / %d Mb/s", (self.appliedOptions ?? options).width, (self.appliedOptions ?? options).height, Double(self.frames) / elapsed, rtt, Double(decodedNS) / 1e6, Double(self.videoBytes) * 8 / elapsed / 1e6, Double(self.quality.bitrate) / 1e6, self.quality.ceiling / 1_000_000))
                                self.frames = 0; self.videoBytes = 0; self.roundTripTotal = 0; self.metricStart = now
                            }
                        } else if kind == .presented, self.authenticated {
                            var r = Reader(data); let sequence = try r.u64()
                            guard data.count == 8, sequence > 0, sequence <= self.lastSequence else { throw AireError("Confirmación del visor inválida.") }
                            // A delayed presentation from the retired capture must not
                            // confirm settings whose first image has not arrived yet.
                            if sequence > self.captureSequenceFloor {
                                self.presentedSequence = sequence; self.confirmPresentedImage()
                            }
                        } else if [.pointer, .keyboard, .desktopControl, .desktopPointer, .desktopKeyboard].contains(kind), self.authenticated {
                            try self.receiveInput(kind, data, reply: { [weak peer] in peer?.send($0, $1) })
                        } else if kind == .failure { throw AireError(String(data: data, encoding: .utf8) ?? "Error del receptor.") }
                        else { throw AireError("Mensaje inesperado.") }
                    } catch { peer.end("\(error)") }
                }
                peer.onEnd = { [weak self, weak peer] reason in
                    guard let self = self, let peer = peer, self.peer === peer else { return }
                    if self.authenticated { self.suspendConnection(reason) }
                    else { self.peer = nil; self.setPhase(.available); self.onStatus?("Conexión rechazada. Esperando una conexión autorizada.") }
                }
                peer.start()
            }
            self.onListenerPrepared?(listener)
            listener.start(queue: self.queue)
        }
    }
    func update(options: StreamOptions) {
        queue.async {
            self.requestedOptions = options
            guard self.active, self.authenticated else { return }
            if !self.adjusting, !self.rebuilding, let applied = self.appliedOptions,
               applied.sameCapture(as: options), let encoder = self.encoder {
                do {
                    self.quality.reconfigure(ceiling: options.bitrate)
                    try encoder.updateBitrate(self.quality.bitrate)
                    encoder.updateQualityLimit(options.maxFrameQP)
                    self.appliedOptions = options
                    self.onOptionsApplied?(options)
                    self.onStatus?("Calidad actualizada. La conexión sigue activa.")
                } catch { self.failSession("\(error)") }
                return
            }
            self.latest.clear()
            self.pointer.releaseButtons()
            self.adjusting = true
            self.setPhase(.applying)
            self.onStatus?("Aplicando ajustes…")
            self.applyWhenDrained()
        }
    }
    private func encodeLatest() {
        defer { drainIdleEncoder() }
        #if arch(x86_64)
        // Enable at the first free input slot. Waiting for both slots to be
        // empty prevented the switch during a continuous stream: one image was
        // always awaiting its ACK. encodeLatest still reserves every slot.
        if encoding == 0, cursorChannel.isReady, window.hasRoom {
            encoder?.enablePipelining()
        }
        #endif
        guard active, authenticated, !adjusting, !rebuilding, window.availableSlots > encoding, encoding < (encoder?.inputCapacity ?? 1),
              let (pixel, timestamp) = latest.take() else { return }
        encoding += 1; encoder?.encode(pixel, capturedAt: timestamp)
        if !encoderWarmed, let encoder = encoder, encoder.inputCapacity > 1, window.availableSlots > encoding {
            encoderWarmed = true; encoding += 1; encoder.encode(pixel, capturedAt: timestamp)
        }
    }
    private func drainIdleEncoder() {
        if let encoder = encoder, encoder.inputCapacity > 1, encoding > 0, window.isEmpty, !latest.hasValue {
            let session = generation
            let submitted = encoder.lastSubmittedSequence
            // Damage-based capture can become idle with the last image still
            // buffered by Intel. Finish it after a bounded idle interval; when
            // images keep arriving, the next input preserves inter-frame coding.
            queue.asyncAfter(deadline: .now()+0.1) { [weak self, weak encoder] in
                guard let self = self, let encoder = encoder, self.active,
                      self.generation == session, self.encoder === encoder,
                      self.encoding > 0, self.window.isEmpty, !self.latest.hasValue,
                      encoder.lastSubmittedSequence == submitted else { return }
                encoder.drain()
            }
        }
    }
    private func applyWhenDrained() {
        if adjusting, encoding > 0, !encoderDrainRequested { encoderDrainRequested = true; encoder?.drain() }
        guard active, authenticated, adjusting, !rebuilding, encoding == 0, window.isEmpty,
              let options = requestedOptions else { return }
        rebuilding = true
        let token = generation
        let previous = capture; capture = nil
        previous?.onPixel = nil; previous?.onError = nil; previous?.onRecoverableError = nil
        let resume = { [weak self] in
            guard let self = self else { return }
            self.queue.async {
                guard self.active, self.generation == token else { return }
                self.encoder?.onFrame = nil; self.encoder?.onError = nil
                self.encoder?.stop(); self.encoder = nil
                self.beginCapture(self.requestedOptions ?? options)
            }
        }
        if let previous = previous { previous.stop(completion: resume) } else { resume() }
    }
    private func beginCapture(_ options: StreamOptions) {
        let token = generation
        rebuilding = true; imageConfirmed = false; captureSequenceFloor = lastSequence; presentedSequence = 0
        setPhase(adjusting ? .applying : .preparing)
        let existingVirtual = virtual
        let previousOptions = appliedOptions
        onMetrics?(""); onStatus?("Conectado. Preparando la pantalla…")
        displayQueue.async {
            // Register before reconfiguration, outside the cursor hot path.
            _ = DisplayGeometry.shared
            let v = existingVirtual ?? ADVirtualScreen(); v.screenSlot = UInt(self.screenSlot); var display = CGMainDisplayID()
            if options.extend {
                var message: NSString?
                let sizeChanged = previousOptions?.width != options.width || previousOptions?.height != options.height
                let ready = v.displayID == 0 ? v.createWidth(UInt(options.width), height: UInt(options.height), error: &message) : (!sizeChanged || v.resizeWidth(UInt(options.width), height: UInt(options.height), error: &message))
                guard ready else {
                    self.queue.async { if self.generation == token { self.stopOnQueue(message as String? ?? "No se pudo crear la pantalla.") } }; return
                }
                display = v.displayID
            } else { v.destroy() }
            self.queue.async {
                guard self.active, self.generation == token else { self.displayQueue.async { if existingVirtual == nil { v.destroy() } }; return }
                do {
                    self.virtual = options.extend ? v : nil
                    if options.extend {
                        let epoch = self.graphicsEpoch
                        let retirementQueue = self.displayQueue
                        self.graphicsMonitor.start { [weak self] in
                            // The input queue can itself be waiting on the
                            // display server. Retire our helper independently.
                            retirementQueue.async { v.destroy() }
                            self?.queue.async {
                                guard let self = self, self.active, self.graphicsEpoch == epoch, self.virtual != nil else { return }
                                self.failSession("macOS está saturando el sistema de color. La extensión se ha detenido para proteger el Mac. Espera a que se recupere; puedes usar Duplicar pantalla.")
                            }
                        }
                    } else { self.graphicsEpoch = UUID(); self.graphicsMonitor.stop() }
                    self.endDesktopControl(); self.pointer.displayID = display
                    self.appliedOptions = options
                    self.peer?.send(.cursorMode, Data([options.nativeCursor ? 1 : 0]))
                    self.startCursor()
                    self.quality = AdaptiveQuality(ceiling: options.bitrate)
                    self.latest.clear()
                    let encoder: H264Encoder
                    func makeEncoder(compatible: Bool) throws -> H264Encoder {
                        try H264Encoder(width: options.width, height: options.height, fps: options.fps, bitrate: self.quality.bitrate, startingSequence: self.lastSequence, maxFrameQP: options.maxFrameQP, pipelined: self.window.availableSlots >= 2, compatibilityLowLatency: compatible)
                    }
                    if self.compatibilityEncoderEnabled {
                        do { encoder = try makeEncoder(compatible: true) }
                        catch { encoder = try makeEncoder(compatible: false) }
                    } else { encoder = try makeEncoder(compatible: false) }
                    self.encoder = encoder; self.encoderWarmed = false; self.encoderDrainRequested = false
                    encoder.onFrame = { [weak self] data in
                        self?.queue.async {
                            guard let self = self, self.active, self.generation == token else { return }
                            self.encoding = max(0, self.encoding-1)
                            do {
                                let frame = try VideoFrame(data)
                                try self.window.sent(sequence: frame.sequence, timestamp: frame.timestamp)
                                self.lastSequence = frame.sequence
                                self.videoBytes += data.count
                                self.peer?.send(.video, data)
                                self.encodeLatest()
                            }
                            catch { self.stopOnQueue("\(error)") }
                        }
                    }
                    encoder.onDropped = { [weak self] in self?.queue.async {
                        guard let self = self, self.active, self.generation == token else { return }
                        self.encoding = max(0, self.encoding-1); self.encodeLatest(); self.applyWhenDrained()
                    }}
                    encoder.onError = { [weak self] error in self?.queue.async { if self?.generation == token { self?.failSession(error) } } }
                    let capture = Capture(); capture.showsCursor = options.nativeCursor; self.capture = capture; self.window.reset(); self.encoding = 0
                    self.frames = 0; self.videoBytes = 0; self.roundTripTotal = 0; self.metricStart = monotonicNS()
                    capture.onPixel = { [weak self, weak capture] pixel in
                        guard let self = self, let capture = capture, self.active, self.capture === capture, self.generation == token else { return }
                        // A damage-based stream can deliver its only image
                        // before start's completion reaches the engine queue.
                        // Retain that image while preparing; encoding remains
                        // blocked until the selected capture is ready.
                        self.latest.offer((pixel, monotonicNS())); self.encodeLatest()
                    }
                    capture.onStatus = { [weak self] status in if self?.generation == token { self?.onStatus?(status) } }
                    capture.onRecoverableError = { [weak self] reason in self?.queue.async {
                        guard let self = self, self.generation == token, self.active, self.authenticated, !self.rebuilding else { return }
                        let now = monotonicNS()
                        self.captureRecoveries = self.captureRecoveries.filter { now - $0 < 30_000_000_000 }
                        guard self.captureRecoveries.count < 3 else { self.suspendConnection("macOS no consigue mantener disponible la pantalla. Se retomará cuando esté disponible."); return }
                        self.captureRecoveries.append(now)
                        self.pointer.releaseButtons(); self.keyboard.releaseKeys(); self.latest.clear()
                        self.adjusting = true; self.onStatus?("La pantalla dejó de estar disponible. Recuperando captura…")
                        self.applyWhenDrained()
                    } }
                    capture.onError = { [weak self] error in self?.queue.async { if self?.generation == token { self?.failSession(error) } } }
                    capture.start(displayID: display, width: options.width, height: options.height, fps: options.fps, queue: self.queue) { [weak self, weak capture] error in
                        self?.queue.async {
                            guard let self = self, let capture = capture, self.active, self.capture === capture, self.generation == token else { return }
                            if let error = error {
                                if capture.startWasTransient { self.suspendConnection(error) }
                                else { self.failSession(error) }
                            }
                            else {
                                self.rebuilding = false
                                self.adjusting = self.requestedOptions != options
                                self.encodeLatest()
                                if self.adjusting { self.applyWhenDrained() }
                                self.onSessionActive?()
                                if !self.adjusting { self.onOptionsApplied?(options) }
                                if !self.imageConfirmed { self.onStatus?("Captura preparada. Esperando la primera imagen en el otro Mac…") }; self.confirmPresentedImage() }
                        }
                    }
                } catch { self.stopOnQueue("\(error)") }
            }
        }
    }
    func reportStartFailure(_ reason: String) { queue.async { self.stopOnQueue(reason) } }
    func releasePointerBeforeExit() {
        let finished = DispatchSemaphore(value: 0)
        queue.async { self.endDesktopControl(); self.pointer.releaseButtons(); self.keyboard.releaseKeys(); finished.signal() }
        _ = finished.wait(timeout: .now()+0.25)
    }
    private func startCursor() {
        let embedded = appliedOptions?.nativeCursor ?? false
        let displayID = pointer.displayID
        let permission = CursorPermission(read: pointer.trusted)
        let session = generation
        let location = cursorLocation
        let sampleCursor: () -> Data = {
            let point = location()
            // Reconfiguration notifications invalidate the cached global origin.
            let normalized = PointerMessage.normalized(point, in: DisplayGeometry.shared.bounds(displayID))
            var body = Data([normalized == nil || embedded ? 0 : 1, permission.value() ? 1 : 0])
            body.append(PointerMessage(action: .move, x: Double(normalized?.x ?? 0), y: Double(normalized?.y ?? 0)).serialize())
            return body
        }
        cursorChannel.sample(sampleCursor, fallback: { [weak self] _, complete in
            guard let self = self else { complete(); return }
            self.queue.async {
                guard self.active, self.authenticated, !self.adjusting, !self.rebuilding, self.generation == session, let peer = self.peer else { complete(); return }
                peer.sendCursor(sampleCursor, completion: complete)
            }
        })
    }
    private func suspendConnection(_ reason: String) {
        streamActivity.stop()
        inputDelivery?.cancel(); inputDelivery = nil
        generation = UUID(); authenticated = false; fastInputUsed = false
        listener?.service = advertisedService
        if let config = pairingConfiguration, let port = listener?.port?.rawValue {
            try? pairing.start(streamPort: port, streamKey: config.key, serviceName: config.service, displayLabel: discoveryLabel)
        }
        endDesktopControl(); cursorChannel.stop(); pointer.releaseButtons(); keyboard.releaseKeys(); pointer.displayID = 0
        let oldPeer = peer; peer = nil; oldPeer?.onEnd = nil; oldPeer?.end()
        latest.clear(); window.reset(); encoding = 0; adjusting = false; rebuilding = false
        encoder?.onFrame = nil; encoder?.onError = nil; encoder?.stop(); encoder = nil
        let oldCapture = capture; capture = nil
        oldCapture?.onPixel = nil; oldCapture?.onError = nil; oldCapture?.onRecoverableError = nil
        if let oldCapture = oldCapture {
            pendingCaptureStops += 1
            oldCapture.stop { [weak self] in
            self?.queue.async {
                guard let self = self else { return }
                self.pendingCaptureStops -= 1
                self.resumeAfterCaptureStop()
            }
        }}
        // Preserve the authenticated session listener and virtual display during a cut.
        // A remembered sender restores this listener identity after relaunch.
        imageConfirmed = false; setPhase(.reconnecting)
        onMetrics?(""); onStatus?("Conexión interrumpida. \(reason) Esperando reconexión del otro Mac…")
    }
    private func resumeAfterCaptureStop() {
        if pendingCaptureStops == 0, active, authenticated, !rebuilding, let options = requestedOptions { beginCapture(options) }
    }
    private func failSession(_ reason: String) {
        guard let peer = peer else { stopOnQueue(reason); return }
        let token = generation
        peer.send(.failure, Data(reason.prefix(512).utf8)) { [weak self] in
            guard let self = self, self.generation == token else { return }; self.stopOnQueue(reason)
        }
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in if self?.generation == token { self?.stopOnQueue(reason) } }
    }
    func stop() { queue.async { self.stopOnQueue("Detenido.", phase: .idle) } }
    private func stopOnQueue(_ reason: String, phase: StreamPhase = .failed) {
        setPhase(phase)
        streamActivity.stop()
        inputDelivery?.cancel(); inputDelivery = nil
        graphicsEpoch = UUID(); graphicsMonitor.stop()
        endDesktopControl(); cursorChannel.stop(); pointer.releaseButtons(); keyboard.releaseKeys(); pointer.displayID = 0
        active = false; generation = UUID(); authenticated = false; window.reset(); latest.clear(); encoding = 0; adjusting = false; rebuilding = false; appliedOptions = nil; requestedOptions = nil
        pairing.stop(); onLink?(nil)
        pairingConfiguration = nil
        listener?.newConnectionHandler = nil; listener?.stateUpdateHandler = nil; listener?.cancel(); listener = nil
        let oldPeer = peer; peer = nil; oldPeer?.onEnd = nil; oldPeer?.end()
        encoder?.onFrame = nil; encoder?.onError = nil; encoder?.stop(); encoder = nil
        let oldCapture = capture; capture = nil; let oldVirtual = virtual; virtual = nil
        // Retire the display even if ScreenCaptureKit never answers stopCapture.
        // This object is not reused by a new session; destroy is idempotent.
        if let oldVirtual = oldVirtual { displayQueue.asyncAfter(deadline: .now()+2) { oldVirtual.destroy() } }
        if let c = oldCapture {
            let cleanupQueue = displayQueue
            pendingCaptureStops += 1
            c.onPixel = nil; c.onError = nil; c.onRecoverableError = nil
            c.stop { [weak self] in cleanupQueue.async {
                oldVirtual?.destroy()
                self?.queue.async { self?.pendingCaptureStops -= 1; self?.resumeAfterCaptureStop() }
            } }
        }
        else { displayQueue.async { oldVirtual?.destroy() } }
        onMetrics?(""); onStatus?(reason)
    }
}
#endif
#if !SENDER || UNIFIED
final class ReceiverEngine {
    var onPeerConnected: ((String) -> Void)?
    // Brightness uses the existing authenticated connection, never a public service.
    var onBrightnessPacket: ((Wire.Kind, Data) -> Void)?
    var onFullscreenRequest: (() -> Void)?
    func sendBrightness(_ kind: Wire.Kind, _ data: Data) {
        guard kind == .brightnessCommand || kind == .brightnessResult, data.count <= 1024 else { return }
        queue.async { [weak self] in
            guard let self = self, self.hello else { return }
            self.peer?.send(kind, data)
        }
    }
    func requestFullscreen() {
        queue.async { [weak self] in
            guard let self = self, self.hello else { return }
            self.peer?.send(.fullscreenCommand)
        }
    }

    let queue = DispatchQueue(label: "AireDisplay.receiver", qos: .userInteractive)
    let streamActivity = StreamActivity()
    var onStatus: ((String) -> Void)?
    var onPhase: ((StreamPhase) -> Void)?
    private(set) var phase = StreamPhase.idle
    private func setPhase(_ value: StreamPhase) {
        guard phase != value else { return }; phase = value; onPhase?(value)
    }
    var onSessionActive: (() -> Void)?
    private var sessionReported = false
    var onMetrics: ((String) -> Void)?
    var onPixel: ((CVPixelBuffer, @escaping (PresentationResult) -> Void) -> Void)?
    private var presentationEpoch: UInt64 = 0
    private var presentationReported = false
    var onClear: (() -> Void)?
    private var peer: Peer?
    private var decoder = H264Decoder()
    private let decodeQueue = DispatchQueue(label: "PrisonDisplay.decode", qos: .userInteractive)
    private var pendingDecodes = 0
    var beforeDecode: (() -> Void)?
    private var hello = false
    private var sequence: UInt64 = 0
    private var generation = UUID()
    private var frames = 0
    private var metricStart = monotonicNS()
    private let cursorChannel = CursorChannel()
    private let cursorDelivery = CursorDeliveryGate()
    var onCursorMode: ((Bool) -> Void)?
    var onCursor: ((Double, Double, Bool, Bool) -> Void)?
    private var desktopInputToken: UInt64?
    private var requestedDesktopToken: UInt64?
    private var inputOnCursor: Bool?
    private var pendingInteractive: [(Wire.Kind, Data)] = []
    private var inputRouteTimeout: DispatchWorkItem?
    private let inputRouteGrace: TimeInterval = 0.12
    var onInteractiveReady: (() -> Void)?
    var onInteractiveStateChanged: ((Bool) -> Void)?
    var onInteractivePending: ((Bool) -> Void)?
    var onNetworkReady: ((NWPath?) -> Void)?
    private func sendInteractive(_ kind: Wire.Kind, _ body: Data) {
        if inputOnCursor == nil {
            if cursorChannel.isReady {
                chooseInteractiveRoute(fast: true)
            } else {
                pendingInteractive.append((kind, body))
                onInteractivePending?(true)
                if pendingInteractive.count == 1 {
                    let token = generation
                    let work = DispatchWorkItem { [weak self] in
                        guard let self = self, self.generation == token, self.inputOnCursor == nil else { return }
                        self.chooseInteractiveRoute(fast: self.cursorChannel.isReady)
                    }
                    inputRouteTimeout = work
                    queue.asyncAfter(deadline: .now() + inputRouteGrace, execute: work)
                } else if pendingInteractive.count >= 256 {
                    chooseInteractiveRoute(fast: false)
                }
                return
            }
        }
        sendInteractiveOnSelectedRoute(kind, body)
    }
    private func chooseInteractiveRoute(fast: Bool) {
        guard inputOnCursor == nil else { return }
        inputOnCursor = fast
        inputRouteTimeout?.cancel(); inputRouteTimeout = nil
        onInteractivePending?(false); onInteractiveStateChanged?(fast)
        let buffered = pendingInteractive; pendingInteractive.removeAll(keepingCapacity: true)
        for (kind, body) in buffered { sendInteractiveOnSelectedRoute(kind, body) }
    }
    private func sendInteractiveOnSelectedRoute(_ kind: Wire.Kind, _ body: Data) {
        if inputOnCursor == true { cursorChannel.sendInput(kind, body) }
        else { peer?.send(kind, body) }
    }
    private func sendInput(_ kind: Wire.Kind, _ body: Data) {
        guard peer != nil else { return }
        if let token = desktopInputToken {
            var tagged = Data(); tagged.u64(token); tagged.append(body)
            sendInteractive(kind == .pointer ? .desktopPointer : .desktopKeyboard, tagged)
        } else { sendInteractive(kind, body) }
    }
    var onDesktopControl: ((DesktopControlMessage) -> Void)?
    var onConnection: ((Bool) -> Void)?
    var onSearchNeeded: (() -> Void)?
    func sendDesktopControl(_ message: DesktopControlMessage) {
        queue.async {
            guard self.hello, self.peer != nil else { return }
            if let recent = self.pendingPointer { self.pendingPointer = nil; self.sendInput(.pointer, recent.serialize()) }
            if message.action == .begin { self.requestedDesktopToken = message.token }
            self.sendInteractive(.desktopControl, message.serialize())
            if message.action == .end, self.requestedDesktopToken == message.token { self.requestedDesktopToken = nil; self.desktopInputToken = nil }
        }
    }
    private func receiveDesktopControl(_ data: Data) throws {
        let message = try DesktopControlMessage(data)
        guard [.accepted, .rejected].contains(message.action) else { throw AireError("Control de escritorio inesperado.") }
        if message.action == .accepted {
            guard requestedDesktopToken == message.token else {
                sendInteractive(.desktopControl, DesktopControlMessage(action: .end, token: message.token).serialize()); return
            }
            desktopInputToken = message.token
        } else if requestedDesktopToken == message.token { desktopInputToken = nil; requestedDesktopToken = nil }
        onDesktopControl?(message)
    }
    private var pendingPointer: PointerMessage?
    private var pointerScheduled = false
    // Diagnostic A/B seam; production sends immediately.
    var pointerDelayMS = 0
    func sendKeyboard(_ message: KeyboardMessage) { queue.async { if self.hello { self.sendInput(.keyboard, message.serialize()) } } }
    func sendPointer(_ message: PointerMessage) {
        queue.async {
            guard self.hello, self.peer != nil else { return }
            if message.action == .move && self.pointerDelayMS > 0 {
                self.pendingPointer = message
                guard !self.pointerScheduled else { return }
                self.pointerScheduled = true
                let token = self.generation
                self.queue.asyncAfter(deadline: .now() + .milliseconds(self.pointerDelayMS)) {
                    guard self.generation == token else { return }
                    self.pointerScheduled = false
                    if let recent = self.pendingPointer { self.pendingPointer = nil; self.sendInput(.pointer, recent.serialize()) }
                }
            } else {
                if let recent = self.pendingPointer { self.pendingPointer = nil; self.sendInput(.pointer, recent.serialize()) }
                self.sendInput(.pointer, message.serialize())
            }
        }
    }
    private let routeResolver = VideoRouteResolver()
    private var retry: DispatchWorkItem?
    private var retryAttempt = 0
    private var reconnectTarget: (NWEndpoint, String, NWEndpoint?)?
    private var sessionApproved = false
    var retryDelay: (Int) -> Double = { min(10, pow(2, Double(min($0, 4)))) }
    func beginPairing() { queue.async {
        self.retry?.cancel(); self.retry = nil; self.reconnectTarget = nil; self.sessionApproved = false
        self.stopOnQueue("Solicitando conexión al otro Mac…", phase: .connecting)
    } }
    func reportStartFailure(_ reason: String) { queue.async {
        self.retry?.cancel(); self.retry = nil; self.reconnectTarget = nil; self.sessionApproved = false
        self.stopOnQueue(reason, phase: .failed)
    } }
    func connect(endpoint: NWEndpoint, key: String, fallback: NWEndpoint? = nil, previouslyApproved: Bool = false) throws {
        _ = try networkParameters(key: key)
        queue.async {
            self.retry?.cancel(); self.retry = nil; self.retryAttempt = 0; self.sessionApproved = previouslyApproved
            self.reconnectTarget = (endpoint, key, fallback)
            self.resolveConnection(endpoint: endpoint, key: key, fallback: fallback)
        }
    }
    private func resolveConnection(endpoint: NWEndpoint, key: String, fallback: NWEndpoint?) {
            self.stopOnQueue("Buscando conexión en la red…", phase: .connecting)
            self.routeResolver.resolve(endpoint, queue: self.queue) { [weak self] selected in
                do {
                    if case .service = selected, !prefersSharedLAN(selected), let local = fallback {
                        // Bonjour can expose AWDL before the shared LAN appears.
                        // Try the authenticated hostname on the LAN before AWDL.
                        try self?.connectResolved(endpoint: local, key: key, fallback: selected)
                    } else { try self?.connectResolved(endpoint: selected, key: key, fallback: fallback) }
                }
                catch { self?.onStatus?("\(error)") }
            }
    }
    private func connectResolved(endpoint: NWEndpoint, key: String, fallback: NWEndpoint?, preferIPv4: Bool = true) throws {
        let params = try networkParameters(key: key)
        let restrictedIPv4 = configureStreamRoute(params, endpoint: endpoint, preferIPv4: preferIPv4)
        do {
            self.stopOnQueue("Conectando…", phase: .connecting)
            let token = UUID(); self.generation = token; self.cursorDelivery.reset(token)
            self.cursorChannel.onUnavailable = { [weak self] _ in
                self?.cursorDelivery.fallback(token)
                self?.queue.async {
                    guard let self = self, self.generation == token else { return }
                    if self.inputOnCursor == nil && !self.pendingInteractive.isEmpty { self.chooseInteractiveRoute(fast: false) }
                    self.onInteractiveStateChanged?(false)
                    if self.inputOnCursor == true { self.peer?.end("El canal de ratón y teclado se interrumpió. Reconectando…") }
                }
            }
            self.cursorChannel.onReady = { [weak self] in self?.queue.async {
                guard let self = self, self.generation == token else { return }
                if self.inputOnCursor == nil && !self.pendingInteractive.isEmpty { self.chooseInteractiveRoute(fast: true) }
                self.onInteractiveStateChanged?(self.inputOnCursor != false); self.onInteractiveReady?()
            } }
            self.cursorChannel.onInput = { [weak self] kind, data in self?.queue.async {
                guard let self = self, self.generation == token, self.hello, kind == .desktopControl else { return }
                do { try self.receiveDesktopControl(data) } catch { self.peer?.end("\(error)") }
            } }
            let peer = Peer(NWConnection(to: endpoint, using: params), queue: self.queue); self.peer = peer
            peer.onReady = { [weak self] in self?.onNetworkReady?(peer.connection.currentPath); peer.send(.hello, Wire.hello(role: "receiver")) }
            peer.onPacket = { [weak self, weak peer] kind, data in
                guard let self = self, let peer = peer, self.peer === peer else { return }
                do {
                    if kind == .hello {
                        guard !self.hello else { throw AireError("Saludo duplicado.") }
                        _ = try Wire.checkHello(data, expected: "sender"); self.onPeerConnected?(try Wire.peerName(data)); self.hello = true; self.streamActivity.start(); self.sessionApproved = true
                        self.setPhase(.preparing); self.onConnection?(true); self.onStatus?("Conectado al otro Mac. Esperando imagen…")
                    } else if kind == .brightnessCommand || kind == .brightnessResult {
                            guard self.hello, data.count <= 1024 else { throw AireError("Ajuste de brillo no autorizado o inválido.") }
                            self.onBrightnessPacket?(kind, data)
                    } else if kind == .fullscreenCommand {
                        guard self.hello else { throw AireError("Orden de pantalla completa no autorizada.") }
                        try Wire.validateFullscreenCommand(data)
                        self.onFullscreenRequest?()
                        } else if kind == .failure, self.hello {
                        guard data.count <= 2048, let reason = String(data: data, encoding: .utf8), !reason.isEmpty else { throw AireError("Error remoto inválido.") }
                        self.sessionApproved = false
                        throw AireError("El otro Mac: " + reason)
                    } else if kind == .desktopControl, self.hello {
                        try self.receiveDesktopControl(data)
                    } else if kind == .cursorMode, self.hello {
                        guard data.count == 1, data[0] <= 1 else { throw AireError("Modo de cursor inválido.") }
                        self.presentationEpoch &+= 1; self.presentationReported = false
                        self.setPhase(self.sessionReported ? .applying : .preparing)
                        self.onCursorMode?(data[0] == 1)
                    } else if kind == .cursorOffer, self.hello {
                        let offer = try CursorOffer(data)
                        // Failure of this optional channel leaves the authenticated video fallback.
                        try? self.cursorChannel.startClient(offer: offer, video: peer.connection) { [weak self] data in
                            guard let position = try? PointerMessage(Data(data.dropFirst(2))) else { return }
                            self?.cursorDelivery.deliver(token, dedicated: true) { self?.onCursor?(position.x, position.y, data[0] == 1, data[1] == 1) }
                        }
                    } else if kind == .cursor, self.hello {
                        guard data.count == PointerMessage.encodedSize + 2, data[0] <= 1, data[1] <= 1 else { throw AireError("Cursor inválido.") }
                        let position = try PointerMessage(Data(data.dropFirst(2)))
                        guard position.action == .move else { throw AireError("Cursor inválido.") }
                        self.cursorDelivery.deliver(token, dedicated: false) { self.onCursor?(position.x, position.y, data[0] == 1, data[1] == 1) }
                    } else if kind == .video, self.hello {
                        let frame = try VideoFrame(data)
                        guard frame.sequence > self.sequence else { throw AireError("Fotograma fuera de orden.") }
                        guard self.pendingDecodes < VideoWindow.capacity else { throw AireError("Demasiadas imágenes pendientes.") }
                        self.sequence = frame.sequence; self.pendingDecodes += 1
                        let decoder = self.decoder; let hook = self.beforeDecode; let renderEpoch = self.presentationEpoch
                        self.decodeQueue.async { [weak self, weak peer] in
                            var pixel: CVPixelBuffer?
                            decoder.onPixel = { pixel = $0 }
                            let start = monotonicNS()
                            do {
                                hook?(); try decoder.decode(frame)
                                let decodeTime = monotonicNS() - start
                                let hardware = decoder.hardware
                                guard let image = pixel else { throw AireError("El decodificador no produjo una imagen.") }
                                self?.queue.async {
                                    guard let self = self, self.generation == token, let peer = peer, self.peer === peer else { return }
                                    self.pendingDecodes -= 1
                                    guard let present = self.onPixel else { peer.end("Visor cerrado."); return }
                                    var ack = Data(); ack.u64(frame.sequence); ack.u64(frame.timestamp); ack.u64(decodeTime); peer.send(.ack, ack)
                                    present(image) { [weak self, weak peer] result in self?.queue.async {
                                        guard let self = self, self.generation == token, self.presentationEpoch == renderEpoch else { return }
                                        if case .failed(let error) = result { peer?.end(error); return }
                                        guard case .accepted = result else { return }
                                        if !self.presentationReported {
                                            self.presentationReported = true
                                            var report = Data(); report.u64(frame.sequence); peer?.send(.presented, report)
                                        }
                                        self.setPhase(.streaming)
                                        if !self.sessionReported {
                                            self.sessionReported = true; self.retryAttempt = 0
                                            self.onSessionActive?()
                                        }
                                    } }
                                    self.frames += 1
                                    let elapsed = Double(monotonicNS() - self.metricStart) / 1e9
                                    if elapsed >= 1 {
                                        let hw = hardware ? "hardware" : "software"
                                        self.onMetrics?(String(format: "%d × %d · %.0f FPS · H.264 %@ · decod. %.1f ms · v%@", CVPixelBufferGetWidth(image), CVPixelBufferGetHeight(image), Double(self.frames) / elapsed, hw, Double(decodeTime) / 1e6, AppVersion.current))
                                        self.frames = 0; self.metricStart = monotonicNS()
                                        self.onStatus?("Recibiendo la pantalla del Mac que envía.")
                                    }
                                }
                            } catch { self?.queue.async { if self?.generation == token { peer?.end("\(error)") } } }
                            decoder.onPixel = nil
                        }
                    } else { throw AireError("Mensaje inesperado.") }
                } catch { peer.end("\(error)") }
            }
            peer.onEnd = { [weak self] reason in
                guard let self = self, self.generation == token else { return }
                let tryIPv6 = !self.hello && restrictedIPv4
                let shouldFallback = !self.hello && fallback != nil
                self.stopOnQueue(reason)
                if tryIPv6 {
                    do { try self.connectResolved(endpoint: endpoint, key: key, fallback: fallback, preferIPv4: false) } catch { self.scheduleReconnect() }
                } else if shouldFallback, let fallback = fallback {
                    do { try self.connectResolved(endpoint: fallback, key: key, fallback: nil) } catch { self.scheduleReconnect() }
                } else { self.scheduleReconnect(reason: reason) }
            }
            peer.start()
        }
    }
    private func scheduleReconnect(reason: String? = nil) {
        guard sessionApproved, let target = reconnectTarget else { onSearchNeeded?(); return }
        retry?.cancel()
        let delay = retryDelay(retryAttempt); retryAttempt += 1
        let token = generation
        setPhase(.reconnecting)
        onStatus?("Reintentando en \(Int(ceil(delay))) s. " + (reason ?? "El otro Mac todavía no está disponible.") + " No necesitas otro código.")
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.generation == token, self.sessionApproved else { return }
            self.retry = nil
            self.resolveConnection(endpoint: target.0, key: target.1, fallback: target.2)
        }
        retry = work; queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
    func stop() { queue.async {
        self.retry?.cancel(); self.retry = nil; self.reconnectTarget = nil; self.sessionApproved = false
        self.stopOnQueue("Desconectado.", phase: .idle)
    } }
    private func stopOnQueue(_ reason: String, phase: StreamPhase = .failed) {
        setPhase(phase)
        streamActivity.stop()
        routeResolver.cancel(); cursorChannel.stop()
        generation = UUID(); cursorDelivery.reset(generation); let p = peer; peer = nil; p?.onEnd = nil; p?.end()
        requestedDesktopToken = nil; desktopInputToken = nil; inputOnCursor = nil; inputRouteTimeout?.cancel(); inputRouteTimeout = nil
        pendingInteractive.removeAll(keepingCapacity: true); onInteractivePending?(false); pendingPointer = nil; pointerScheduled = false
        let oldDecoder = decoder; decoder = H264Decoder(); pendingDecodes = 0
        decodeQueue.async { oldDecoder.stop(); oldDecoder.onPixel = nil }
        hello = false; sequence = 0
        onInteractiveStateChanged?(false)
        presentationEpoch &+= 1; presentationReported = false
        sessionReported = false; frames = 0; metricStart = monotonicNS(); onConnection?(false); onClear?(); onStatus?(reason)
    }
}
#endif

final class LatestCursorPresenter {
    private let lock = NSLock()
    private var latest: (Double, Double, Bool, Bool)?
    private var scheduled = false
    private var generation: UInt64 = 0
    private let render: (Double, Double, Bool, Bool) -> Void
    init(render: @escaping (Double, Double, Bool, Bool) -> Void) { self.render = render }
    func submit(x: Double, y: Double, visible: Bool, permitted: Bool) {
        lock.lock(); latest = (x, y, visible, permitted)
        let schedule = !scheduled; scheduled = true; let token = generation; lock.unlock()
        guard schedule else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            guard self.generation == token else { self.lock.unlock(); return }
            let value = self.latest; self.latest = nil; self.scheduled = false; self.lock.unlock()
            if let v = value { self.render(v.0, v.1, v.2, v.3) }
        }
    }
    func clear() { lock.lock(); latest = nil; scheduled = false; generation &+= 1; lock.unlock() }
}

enum PresentationResult { case accepted, skipped, failed(String) }

final class LatestVideoPresenter {
    private let lock = NSLock()
    private var latest: (CVPixelBuffer, (PresentationResult) -> Void)?
    private var scheduled = false
    private var generation: UInt64 = 0
    private let render: (CVPixelBuffer) throws -> Bool
    init(render: @escaping (CVPixelBuffer) throws -> Bool) { self.render = render }
    func submit(_ pixel: CVPixelBuffer, completion: @escaping (PresentationResult) -> Void) {
        lock.lock()
        let replaced = latest
        latest = (pixel, completion)
        let shouldSchedule = !scheduled
        scheduled = true
        let token = generation
        lock.unlock()
        replaced?.1(.skipped)
        guard shouldSchedule else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            guard self.generation == token else { self.lock.unlock(); return }
            let frame = self.latest; self.latest = nil; self.scheduled = false
            self.lock.unlock()
            guard let frame = frame else { return }
            do { frame.1(try self.render(frame.0) ? .accepted : .skipped) } catch { frame.1(.failed("\(error)")) }
        }
    }
    func clear() {
        lock.lock()
        let frame = latest; latest = nil; scheduled = false; generation &+= 1
        lock.unlock()
        frame?.1(.skipped)
    }
}

#if !UNIFIED
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private(set) var expertMode = false
    private var advancedViews: [NSView] = []
    private var manualView: NSView?
    private var manualExpanded = false
    private var manualHelpButton: NSButton?
    func setExpertMode(_ enabled: Bool) {
        expertMode = enabled
        #if !SENDER
        primary.isHidden = !enabled
        #endif
        for view in advancedViews { view.isHidden = !enabled }
        metrics.isHidden = !enabled || metrics.stringValue.isEmpty
        manualView?.isHidden = !enabled && !manualExpanded
        manualHelpButton?.isHidden = enabled
        window?.contentView?.layoutSubtreeIfNeeded()
    }
    @objc private func toggleManualHelp() {
        manualExpanded.toggle(); manualView?.isHidden = !expertMode && !manualExpanded
        manualHelpButton?.title = manualExpanded ? "Ocultar conexión por enlace" : "¿No aparece el Mac? Conectar con enlace…"
    }

    let hosted: Bool
    private let trustAccount: String
    let screenSlot: Int
    private(set) var workspaceActive = false
    init(hosted: Bool = false, trustAccount: String? = nil, screenSlot: Int = 0) {
        self.screenSlot = screenSlot
        self.hosted = hosted
        self.trustAccount = trustAccount ?? Bundle.main.bundleIdentifier ?? "local.prisondisplay.tests"
        super.init()
    }
    var window: NSWindow!
    var viewer: NSWindow?
    let video = VideoView(frame: .zero)
    private lazy var cursorPresenter = LatestCursorPresenter { [weak self] x, y, visible, permitted in
        self?.video.remoteCursor(x: x, y: y, visible: visible)
        if self?.inputPermitted != permitted {
            self?.inputPermitted = permitted; self?.updateInputState()
        }
    }
    private lazy var presenter = LatestVideoPresenter { [weak self] pixel in
        guard let self = self else { throw AireError("Visor cerrado.") }
        return try self.video.present(pixel)
    }
    let connectionOverview = PrisonConnectionOverview()
    let connectionState = NSTextField(wrappingLabelWithString: StreamPhase.idle.title)
    let inputState = NSTextField(wrappingLabelWithString: "Ratón y teclado: esperando conexión")
    private var inputPermitted: Bool?
    private var fastInputReady = false
    private var fastInputPending = false
    private var currentPhase = StreamPhase.idle
    private var permissionTimer: Timer?
    #if SENDER
    let settingsState = NSTextField(wrappingLabelWithString: "Ajustes guardados · se aplicarán al conectar")
    #else
    let keyboardSwitch = NSButton(checkboxWithTitle: "Usar este teclado en la pantalla recibida", target: nil, action: nil)
    #endif
    let status = NSTextField(wrappingLabelWithString: "Listo.")
    let metrics = NSTextField(labelWithString: "")
    let key = NSTextField(string: "")
    private lazy var trustStore = TrustStore(account: trustAccount)
    private var rememberedProfile: TrustedProfile?
    private var trustReadError: String?
    private var trustRecovery: UUID?
    private var trustReadPending = false
    private var trustWritePending = false
    private let trustQueue = DispatchQueue(label: "PrisonDisplay.trust", qos: .userInitiated)
    var loadRememberedConnection: ((Bool) throws -> TrustedProfile?)?
    let recoverConnection = PrisonSecondaryButton(title: "Recuperar conexión guardada…", target: nil, action: nil)
    var recoverConnectionRow: NSView?
    let trustExplanation = NSTextField(wrappingLabelWithString: "")
    private var currentSessionLink: ConnectionLink?
    private var sessionHasImage = false
    private var connectedPeerName: String?
    let rememberConnection = NSButton(checkboxWithTitle: "Reconectar automáticamente", target: nil, action: nil)
    let primary = PrisonActionButton(title: "", target: nil, action: nil)
    let disconnect = PrisonSecondaryButton(title: "", target: nil, action: nil)
    #if SENDER
    let engine = SenderEngine()
    let mode = PrisonPopUpButton()
    let resolution = PrisonPopUpButton()
    let fps = PrisonPopUpButton()
    let quality = PrisonPopUpButton()
    let cursorStyle = PrisonPopUpButton()
    var connectionLink: ConnectionLink?
    let copyLink = PrisonSecondaryButton(title: "Copiar enlace de conexión", target: nil, action: nil)
    #else
    let engine = ReceiverEngine()
    let desktopBridge = DesktopBridge()
    let desktopToggle = NSButton(checkboxWithTitle: "Cruzar al escritorio propio del otro Mac", target: nil, action: nil)
    let desktopEdge = PrisonPopUpButton()
    let desktopStatus = NSTextField(wrappingLabelWithString: "Desactivado. El ratón y teclado siguen en este Mac.")
    let devices = PrisonPopUpButton()
    let pairing = PairingClient(queue: DispatchQueue(label: "AireDisplay.pairing", qos: .userInitiated))
    var browser: NWBrowser?
    var endpoints: [NWEndpoint] = []
    let deviceList = PrisonStack()
    private var deviceActions: [NSButton] = []
    private var discoveryRetry: DispatchWorkItem?
    private var discoveryGeneration = UUID()
    private var searching = true
    private var awaitingPairing = false
    private var pairingAttempt = UUID()
    var requestDeviceConnection: ((NWEndpoint) -> Void)?
    var startDiscovery: ((NWBrowser) -> Void)?
    var discoveryRetryDelay: Double = 5
    private var discoveryMessage: String?
    private var savedDeviceName: String { connectedPeerName ?? rememberedProfile?.host.replacingOccurrences(of: ".local", with: "") ?? "Mac enlazado" }

    #endif
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu(); let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Acerca de PRISON DISPLAY v\(AppVersion.current)", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); editItem.title = "Editar"; menu.addItem(editItem); let edit = NSMenu(title: "Editar"); editItem.submenu = edit
        edit.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        if !hosted { NSApp.mainMenu = menu }
        rememberConnection.state = ReconnectPreference.enabled(account: trustAccount) ? .on : .off
        rememberConnection.target = self; rememberConnection.action = #selector(toggleRemember)
        rememberConnection.toolTip = "Después de aprobar el primer enlace, conecta sin códigos al abrir las apps. Guarda la autorización solo en el Llavero de este Mac."
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: min(980, (NSScreen.main?.visibleFrame.height ?? 1060)-60)), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.delegate = self
        window.minSize = NSSize(width: 600, height: 540)
        #if SENDER
        window.title = "PRISON DISPLAY · Enviar · v\(AppVersion.current)"
        #else
        window.title = "PRISON DISPLAY · Recibir · v\(AppVersion.current)"
        #endif
        if #available(macOS 10.14, *) { window.appearance = NSAppearance(named: .darkAqua) } else { window.appearance = NSAppearance(named: .vibrantDark) }
        window.backgroundColor = NSColor(calibratedRed: 0.065, green: 0.075, blue: 0.09, alpha: 1)
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(scroll)
        let content = window.contentView!
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor), scroll.topAnchor.constraint(equalTo: content.topAnchor), scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        let root = PrisonStack(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 12, left: 24, bottom: 24, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false
        let document = PrisonDocument(); document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document; document.addSubview(root)
        let fill = root.widthAnchor.constraint(equalTo: document.widthAnchor); fill.priority = .defaultHigh
        NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor), root.centerXAnchor.constraint(equalTo: document.centerXAnchor), root.topAnchor.constraint(equalTo: document.topAnchor), root.bottomAnchor.constraint(equalTo: document.bottomAnchor), root.widthAnchor.constraint(lessThanOrEqualTo: document.widthAnchor), root.widthAnchor.constraint(lessThanOrEqualToConstant: 920), fill])
        let header = PrisonHeader(); header.wantsLayer = true; header.layer?.cornerRadius = 16; header.layer?.masksToBounds = true
        root.addArrangedSubview(header); header.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -48).isActive = true
        header.heightAnchor.constraint(equalToConstant: hosted ? 0 : 100).isActive = true
        header.isHidden = hosted
        #if SENDER
        if !hosted { sectionLabel("ENVIAR PANTALLA", in: root) }
        #else
        if !hosted { sectionLabel("RECIBIR PANTALLA", in: root) }
        #endif
        #if SENDER
        if !hosted { addText("Más espacio. La misma libertad.", to: root) }
        let settings = card("AJUSTES AVANZADOS DE IMAGEN", in: root)
        if let box = settings.superview { advancedViews.append(box) }
        mode.addItems(withTitles: ["Extender escritorio", "Duplicar esta pantalla"])
        resolution.addItems(withTitles: ["1920 × 1080", "1280 × 720", "2560 × 1440"])
        fps.addItems(withTitles: ["60 FPS", "30 FPS"])
        cursorStyle.addItems(withTitles: ["Rápido · mínimo retraso", "Original · formas exactas"])
        quality.addItems(withTitles: VideoQualityProfile.all.map { $0.title })
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let saved = DisplayPreferences(compatibilityDefaults: system.majorVersion == 10 && system.minorVersion == 13, screenSlot: screenSlot)
        mode.selectItem(at: saved.mode); resolution.selectItem(at: saved.resolution)
        fps.selectItem(at: saved.fps); quality.selectItem(at: saved.quality); cursorStyle.selectItem(at: saved.cursor)
        if !virtualDisplaySupported {
            mode.item(at: 0)?.isEnabled = false; mode.selectItem(at: 1)
            addText("Este macOS permite enviar una pantalla duplicada. Para extender desde este equipo necesita un sistema que admita pantallas virtuales. Puedes recibir aquí el escritorio extendido de otro Mac.", to: settings)
        }
        for control in [mode, resolution, fps, quality, cursorStyle] { control.target = self; control.action = #selector(settingsChanged) }
        row("Modo", mode, in: settings); row("Resolución", resolution, in: settings); row("Fluidez", fps, in: settings); row("Calidad", quality, in: settings); row("Cursor", cursorStyle, in: settings)
        addText("Rápido prioriza el movimiento. Original muestra los cursores de FL Studio y otras apps dentro del vídeo.", to: settings)
        addText("La calidad marca el máximo. 40 Mb/s aprovecha enlaces rápidos; la app adapta el vídeo si el Wi-Fi se satura. No depende de la velocidad de Internet.", to: settings)
        let connection = card("Conexión", in: root)
        connection.addArrangedSubview(connectionOverview)
        connectionOverview.widthAnchor.constraint(equalTo: connection.widthAnchor).isActive = true
        connectionOverview.heightAnchor.constraint(equalToConstant: 166).isActive = true
        key.stringValue = rememberedProfile?.key ?? ((try? newPairingKey()) ?? ""); key.isEditable = false; key.isSelectable = true
        copyLink.target = self; copyLink.action = #selector(copyConnectionLink); copyLink.isEnabled = false

        engine.onLink = { [weak self] link in DispatchQueue.main.async { self?.connectionLink = link; self?.currentSessionLink = link; self?.copyLink.isEnabled = link != nil; self?.updateConnectionActions() } }
        engine.onConfirm = { [weak self] name, code, done in self?.confirmConnection(name: name, code: code, done: done) }
        primary.title = "Hacer disponible este Mac"; primary.target = self; primary.action = #selector(start)
        disconnect.title = "Detener"; disconnect.target = self; disconnect.action = #selector(stop); buttons([primary, disconnect], in: connection)
        addText("Confirma el código en ambos Mac la primera vez. Después se reconectarán solos.", to: connection)
        let tools = card("RATÓN Y COLOCACIÓN", in: root)
        let mousePermission = PrisonSecondaryButton(title: "Permitir ratón y teclado…", target: self, action: #selector(allowMouse))
        let displays = PrisonSecondaryButton(title: "Organizar pantallas", target: self, action: #selector(openDisplays))
        buttons([mousePermission, displays], in: tools)
        tools.addArrangedSubview(settingsState)
        advancedViews.append(settingsState)
        settingsState.font = .systemFont(ofSize: 12); settingsState.textColor = prisonSecondaryText
        settingsState.widthAnchor.constraint(equalTo: tools.widthAnchor).isActive = true
        #else
        if !hosted { addText("Convierte este Mac en la pantalla del otro.", to: root) }
        let connection = card("ELEGIR UN MAC", in: root)
        devices.addItem(withTitle: "Buscando Macs disponibles…")
        devices.controlSize = .regular; devices.font = .systemFont(ofSize: 14)
        devices.isHidden = true // Retain selection for keyboard and existing diagnostics.
        connection.addArrangedSubview(devices)
        deviceList.orientation = .vertical; deviceList.alignment = .leading; deviceList.spacing = 10
        connection.addArrangedSubview(deviceList)
        deviceList.widthAnchor.constraint(equalTo: connection.widthAnchor).isActive = true
        renderDevices()
        devices.widthAnchor.constraint(equalTo: connection.widthAnchor).isActive = true
        devices.heightAnchor.constraint(equalToConstant: 34).isActive = true
        addText("Pulsa Conectar junto al Mac que quieres usar. En ese equipo elige Enviar pantalla. La primera vez, confirma el código en ambos.", to: connection)
        configurePairingCallbacks()
        engine.onSearchNeeded = { [weak self] in DispatchQueue.main.async { if self?.hosted != true || self?.workspaceActive == true { self?.browse() } } }
        primary.title = "Conectar al otro Mac"; primary.target = self; primary.action = #selector(start)
        disconnect.title = "Desconectar"; disconnect.target = self; disconnect.action = #selector(stop); buttons([primary, disconnect], in: connection)
        let screen = card("VER PANTALLA", in: root)
        screen.superview?.isHidden = hosted
        let full = PrisonSecondaryButton(title: "Abrir pantalla completa", target: self, action: #selector(fullscreen))
        buttons([full], in: screen)
        addText("Pulsa Esc para salir de pantalla completa.", to: screen)
        let input = card("TECLADO EN EL VISOR", in: root)
        let savedInput = ReceiverPreferences()
        keyboardSwitch.state = savedInput.keyboard ? .on : .off; video.keyboardEnabled = savedInput.keyboard
        keyboardSwitch.target = self; keyboardSwitch.action = #selector(toggleKeyboard)
        input.addArrangedSubview(keyboardSwitch)
        addText("Activa esta opción y haz clic en la imagen: lo que escribas irá al Mac que envía. Copiar, pegar y los atajos funcionan allí. ⌘Q, ⌘H y ⌘Tab se quedan en este Mac.", to: input)
        let desktop = card("RATÓN Y TECLADO ENTRE EQUIPOS", in: root)
        if let box = desktop.superview { advancedViews.append(box) }
        desktopToggle.state = savedInput.crossing ? .on : .off
        if savedInput.crossing { desktopStatus.stringValue = "Cruce guardado · se activará cuando llegue la imagen del Mac que envía." }
        desktopToggle.target = self; desktopToggle.action = #selector(toggleDesktop)
        desktop.addArrangedSubview(desktopToggle)
        for edge in DesktopEdge.allCases { desktopEdge.addItem(withTitle: edge.title) }
        desktopEdge.selectItem(at: savedInput.edge)
        desktopBridge.edge = DesktopEdge(rawValue: desktopEdge.indexOfSelectedItem) ?? .right
        desktopEdge.target = self; desktopEdge.action = #selector(changeDesktopEdge)
        row("Posición", desktopEdge, in: desktop)
        addText("Cruza por ese borde para controlar el escritorio propio del Mac que envía. Vuelve por el mismo borde o pulsa ⌃⌥Esc. No mueve ventanas entre las apps propias de los dos equipos.", to: desktop)
        desktopStatus.font = .systemFont(ofSize: 12); desktopStatus.textColor = prisonSecondaryText
        desktop.addArrangedSubview(desktopStatus)
        desktopStatus.widthAnchor.constraint(equalTo: desktop.widthAnchor).isActive = true
        let desktopPermission = PrisonSecondaryButton(title: "Permitir control desde este Mac…", target: self, action: #selector(openDesktopPermission))
        buttons([desktopPermission], in: desktop)
        desktopBridge.sendControl = { [weak self] in self?.engine.sendDesktopControl($0) }
        desktopBridge.sendPointer = { [weak self] in self?.engine.sendPointer($0) }
        desktopBridge.sendKeyboard = { [weak self] in self?.engine.sendKeyboard($0) }
        desktopBridge.onControlChanged = { [weak self] in self?.video.desktopControlActive = $0 }
        desktopBridge.onStatus = { [weak self] in self?.desktopStatus.stringValue = $0 }
        desktopBridge.onDisabled = { [weak self] in
            self?.desktopToggle.state = .off
            self?.saveInputPreferences()
        }
        engine.onConnection = { [weak self] connected in DispatchQueue.main.async { if !connected { self?.desktopBridge.connected = false } } }
        engine.onFullscreenRequest = { [weak self] in DispatchQueue.main.async { self?.enterViewerFullscreen() } }
        engine.onDesktopControl = { [weak self] message in DispatchQueue.main.async { self?.desktopBridge.reply(message) } }
        engine.onClear = { [weak self] in DispatchQueue.main.async { self?.presenter.clear(); self?.cursorPresenter.clear(); self?.video.clear() } }
        engine.onPixel = { [weak self] pixel, done in
            guard let self = self else { done(.failed("Visor cerrado.")); return }
            guard !self.hosted || self.workspaceActive else { done(.skipped); return }
            self.presenter.submit(pixel, completion: done)
        }
        engine.onCursorMode = { [weak self] embedded in DispatchQueue.main.async { self?.video.cursorInVideo = embedded } }
        video.onKeyboard = { [weak self] message in self?.engine.sendKeyboard(message) }
        video.onPointer = { [weak self] message in self?.engine.sendPointer(message) }
        _ = cursorPresenter
        engine.onCursor = { [weak self] x, y, visible, permitted in
            self?.cursorPresenter.submit(x: x, y: y, visible: visible, permitted: permitted)
        }
        engine.onInteractiveStateChanged = { [weak self] ready in DispatchQueue.main.async {
            self?.fastInputReady = ready; self?.updateInputState()
        } }
        engine.onInteractivePending = { [weak self] pending in DispatchQueue.main.async {
            self?.fastInputPending = pending; self?.updateInputState()
        } }
        addText("Para usar también el ratón de este Mac, permite su acceso desde la app del Mac que envía.", to: input)
        if !hosted && !CommandLine.arguments.contains("--layout-preview") { browse() }
        #endif
        connection.addArrangedSubview(rememberConnection)
        trustExplanation.stringValue = trustReadError ?? "Guarda este enlace en el Llavero para reconectar sin códigos."
        trustExplanation.font = .systemFont(ofSize: 13); trustExplanation.textColor = prisonSecondaryText
        trustExplanation.setContentCompressionResistancePriority(.required, for: .vertical)
        connection.addArrangedSubview(trustExplanation)
        trustExplanation.widthAnchor.constraint(equalTo: connection.widthAnchor).isActive = true
        recoverConnection.target = self; recoverConnection.action = #selector(restoreRememberedConnection)
        recoverConnection.isHidden = trustReadError == nil
        buttons([recoverConnection], in: connection)
        recoverConnectionRow = connection.arrangedSubviews.last
        recoverConnectionRow?.isHidden = trustReadError == nil
        #if SENDER
        engine.onFirstImage = { [weak self] in DispatchQueue.main.async {
            self?.sessionHasImage = true; self?.rememberCurrentSession()
        } }
        engine.onOptionsApplied = { [weak self] options in DispatchQueue.main.async {
            self?.settingsState.stringValue = "Aplicados · \(options.width) × \(options.height) · objetivo \(options.fps) FPS · hasta \(options.bitrate / 1_000_000) Mb/s"
        } }
        #else
        engine.onSessionActive = { [weak self] in DispatchQueue.main.async {
            self?.sessionHasImage = true; self?.rememberCurrentSession(); self?.renderDevices()
        } }
        #endif
        let stateCard = card("ESTADO", in: root)
        connectionState.font = .systemFont(ofSize: 16, weight: .semibold)
        inputState.font = .systemFont(ofSize: 13); inputState.textColor = prisonSecondaryText
        for label in [connectionState, inputState] {
            stateCard.addArrangedSubview(label)
            label.setContentCompressionResistancePriority(.required, for: .vertical)
            label.widthAnchor.constraint(equalTo: stateCard.widthAnchor).isActive = true
        }
        engine.onPhase = { [weak self] phase in DispatchQueue.main.async { self?.displayPhase(phase) } }
        status.font = .systemFont(ofSize: 14, weight: .medium); status.textColor = .white; stateCard.addArrangedSubview(status)
        status.setContentCompressionResistancePriority(.required, for: .vertical)
        status.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        status.widthAnchor.constraint(equalTo: stateCard.widthAnchor).isActive = true
        metrics.isHidden = true
        metrics.font = .systemFont(ofSize: 11); metrics.textColor = prisonSecondaryText; stateCard.addArrangedSubview(metrics)
        metrics.setContentCompressionResistancePriority(.required, for: .vertical)
        metrics.lineBreakMode = .byWordWrapping; metrics.maximumNumberOfLines = 3; metrics.widthAnchor.constraint(equalTo: stateCard.widthAnchor).isActive = true
        primary.bezelStyle = .rounded; primary.bezelColor = prisonAccent; if #available(macOS 10.14, *) { primary.contentTintColor = .white }; primary.font = .systemFont(ofSize: 14, weight: .semibold)
        primary.keyEquivalent = "\r"
        let help = PrisonSecondaryButton(title: "¿No aparece el Mac? Conectar con enlace…", target: self, action: #selector(toggleManualHelp))
        manualHelpButton = help; root.addArrangedSubview(help)
        help.heightAnchor.constraint(equalToConstant: 38).isActive = true
        help.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -48).isActive = true
        let manual = card("CONEXIÓN POR ENLACE", in: root)
        manualView = manual.superview
        #if SENDER
        addText("Si el otro Mac no encuentra este equipo, copia el enlace y pégalo en su app.", to: manual)
        buttons([copyLink], in: manual)
        #else
        addText("Si no aparece el otro Mac, copia allí el enlace y pégalo aquí.", to: manual)
        let pasteLink = PrisonSecondaryButton(title: "Pegar enlace de conexión", target: self, action: #selector(pasteConnectionLink))
        buttons([pasteLink], in: manual)
        #endif
        if !hosted { addText("PRISON DISPLAY  ·  v\(AppVersion.current)  ·  Conexión local cifrada", to: root) }
        if hosted, let box = connection.superview { root.removeArrangedSubview(box); root.insertArrangedSubview(box, at: 1) }
        // Keep the actionable computer list ahead of secondary diagnostics.
        if let box = stateCard.superview {
            root.removeArrangedSubview(box); root.insertArrangedSubview(box, at: hosted ? 2 : 1)
        }
        engine.onStatus = { [weak self] text in DispatchQueue.main.async {
            guard let self = self else { return }
            if self.currentPhase != .streaming && self.status.stringValue != text {
                os_log("%{public}@ · %{public}@", log: OSLog(subsystem: "local.prisondisplay", category: "detail"), type: .default, Host.current().localizedName ?? "Este Mac", text)
            }
            self.status.stringValue = text; self.video.updateStatus(text)
        } }
        #if !SENDER
        engine.onPeerConnected = { [weak self] name in DispatchQueue.main.async {
            self?.connectedPeerName = name; self?.updateConnectionActions()
        } }
        #endif
        engine.onMetrics = { [weak self] text in DispatchQueue.main.async { self?.metrics.stringValue = text; self?.metrics.isHidden = self?.expertMode != true || text.isEmpty } }
        updateConnectionActions()
        setExpertMode(false)
        window.center()
        if !hosted && !CommandLine.arguments.contains("--layout-preview") {
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            #if SENDER
            start() // Advertise immediately; capture still requires an authenticated receiver.
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateInputState() }
            #endif
            // Only one read, after the window exists, off the main thread. A
            // cancelled authorization stays cancelled until an explicit retry.
            readRememberedConnection()
        }
    }
    func activateWorkspace() {
        guard !workspaceActive else { return }
        workspaceActive = true
        guard !CommandLine.arguments.contains("--layout-preview") else { return }
        #if SENDER
        if rememberedProfile == nil { start() }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateInputState() }
        #else
        browse()
        #endif
        readRememberedConnection()
    }
    func deactivateWorkspace() {
        workspaceActive = false
        cancelTrustRecovery(); permissionTimer?.invalidate(); permissionTimer = nil
        #if SENDER
        engine.releasePointerBeforeExit()
        #else
        awaitingPairing = false; pairingAttempt = UUID()
        desktopBridge.stop(); video.releaseLocalButtons(); video.releaseKeyboard(); presenter.clear(); cursorPresenter.clear(); video.clear()
        pairing.queue.async { self.pairing.stop() }
        discoveryRetry?.cancel(); discoveryRetry = nil; discoveryGeneration = UUID()
        browser?.cancel(); browser = nil
        viewer?.orderOut(nil)
        #endif
        engine.stop()
    }
    func displayPeerName(_ name: String) {
        connectedPeerName = name; updateConnectionActions()
    }
    func displayPhase(_ phase: StreamPhase) {
        // Connection metadata only: no images, credentials, keys or input content.
        // Enables verification of the receiver's actual UI state over the already
        // authorized diagnostic connection without automating its desktop.
        #if SENDER
        let role = "Enviar \(screenSlot + 1)"
        #else
        let role = "Recibir"
        #endif
        os_log("%{public}@ v%{public}@ · %{public}@", log: OSLog(subsystem: "local.prisondisplay", category: "connection"), type: .default, role, AppVersion.current, phase.title)
        if hosted && !workspaceActive && !CommandLine.arguments.contains("--layout-preview") { return }
        currentPhase = phase; connectionOverview.live = phase == .streaming; updateConnectionActions()
        connectionState.stringValue = phase.title; connectionState.textColor = phase.color
        #if !SENDER
        desktopBridge.connected = phase == .streaming
        if phase == .streaming, desktopToggle.state == .on, !desktopBridge.isActive, !CommandLine.arguments.contains("--layout-preview") {
            do { try desktopBridge.start() }
            catch { desktopToggle.state = .off; desktopStatus.stringValue = "\(error)" }
        }
        #endif
        if phase != .streaming && phase != .applying {
            inputPermitted = nil; sessionHasImage = false; fastInputReady = false; fastInputPending = false
        }
        updateInputState()
    }
    func updateConnectionActions() {
        connectionOverview.remoteName = connectedPeerName ?? rememberedProfile?.host.replacingOccurrences(of: ".local", with: "") ?? "Otra pantalla"
        let ready = currentPhase == .idle || currentPhase == .failed || currentPhase == .available
        let live = currentPhase == .streaming || currentPhase == .applying
        #if SENDER
        primary.isEnabled = ready && connectionLink == nil && currentPhase != .available
        primary.title = live ? "Conectado a \(connectedPeerName ?? "otro Mac")" : (currentPhase == .available ? "Este Mac está disponible" : (ready ? "Iniciar conexión" : "Conectando…"))
        disconnect.isEnabled = !ready || connectionLink != nil || currentPhase == .available
        #else
        primary.isEnabled = ready && !endpoints.isEmpty
        primary.title = live ? "Conectado a \(connectedPeerName ?? "otro Mac")" : (ready ? "Conectar al otro Mac" : "Conectando…")
        devices.isEnabled = ready
        renderDevices()
        disconnect.isEnabled = !ready
        #endif
    }
    func updateInputState() {
        #if SENDER
        inputState.stringValue = AXIsProcessTrusted() ? "Control desde el otro Mac · permiso concedido" : "Control desde el otro Mac · falta Accesibilidad en este Mac"
        #else
        guard currentPhase == .streaming else {
            inputState.stringValue = "Ratón y teclado · esperando imagen y permiso del Mac que envía"
            return
        }
        if inputPermitted == true {
            let transport = fastInputPending ? "preparando canal rápido" : (fastInputReady ? "canal rápido conectado" : "canal de vídeo")
            inputState.stringValue = "Ratón de este Mac · \(transport). Teclado del visor · " + (video.keyboardEnabled ? "activado" : "desactivado")
        } else if inputPermitted == false {
            inputState.stringValue = "Ratón y teclado · falta Accesibilidad en el Mac que envía"
        } else { inputState.stringValue = "Ratón y teclado · comprobando permiso del Mac que envía…" }
        #endif
    }
    func sectionLabel(_ text: String, in stack: NSStackView) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .bold); label.textColor = prisonAccent
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        stack.addArrangedSubview(label)
        if stack.edgeInsets.top > 0 { stack.setCustomSpacing(6, after: label) }
    }
    func card(_ title: String, in stack: NSStackView) -> NSStackView {
        // Constrain the contents directly to the card. NSBox content geometry differs on Catalina.
        let box = NSView(); box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(calibratedRed: 0.105, green: 0.115, blue: 0.14, alpha: 1).cgColor
        box.layer?.borderColor = NSColor(calibratedRed: 0.19, green: 0.20, blue: 0.23, alpha: 1).cgColor
        box.layer?.borderWidth = 1; box.layer?.cornerRadius = 12
        box.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(box)
        box.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true
        let inner = PrisonStack(); inner.orientation = .vertical; inner.alignment = .leading; inner.spacing = 10
        inner.translatesAutoresizingMaskIntoConstraints = false; box.addSubview(inner)
        NSLayoutConstraint.activate([inner.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 18), inner.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -18), inner.topAnchor.constraint(equalTo: box.topAnchor, constant: 18), inner.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -18)])
        sectionLabel(title, in: inner)
        return inner
    }
    func addText(_ text: String, to stack: NSStackView) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13); label.textColor = prisonSecondaryText
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        stack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true
    }
    func row(_ text: String, _ control: NSView, in stack: NSStackView) {
        let row = NSStackView(); row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 16
        let label = NSTextField(labelWithString: text); label.font = .systemFont(ofSize: 14, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true
        row.addArrangedSubview(label); row.addArrangedSubview(control); stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -116).isActive = true
        control.heightAnchor.constraint(equalToConstant: 34).isActive = true
        control.setContentCompressionResistancePriority(.required, for: .vertical)
        if let popup = control as? NSPopUpButton { popup.font = .systemFont(ofSize: 14); popup.controlSize = .regular }
    }
    func buttons(_ controls: [NSButton], in stack: NSStackView) {
        for button in controls {
            button.bezelStyle = .rounded; button.controlSize = .regular
            button.font = .systemFont(ofSize: 13, weight: .medium)
            button.heightAnchor.constraint(equalToConstant: 42).isActive = true
            button.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        let row = NSStackView(views: controls); row.orientation = .horizontal
        row.distribution = .fillEqually; row.spacing = 14; row.alignment = .centerY
        stack.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    func rememberCurrentSession() {
        guard !hosted || workspaceActive else { return }
        guard rememberConnection.state == .on, !trustWritePending else { return }
        guard sessionHasImage, let link = currentSessionLink else {
            trustExplanation.stringValue = "Se guardará cuando llegue la primera imagen del otro Mac."
            return
        }
        do {
            let profile = try TrustedProfile(link)
            if rememberedProfile == profile { trustExplanation.stringValue = "Conexión guardada · reconexión sin códigos al abrir las apps."; return }
            trustWritePending = true; rememberConnection.isEnabled = false; recoverConnection.isEnabled = false
            trustExplanation.stringValue = "Guardando la conexión en el Llavero…"
            trustQueue.async { [weak self] in
                guard let self = self else { return }
                let result = Result { try self.trustStore.save(profile) }
                DispatchQueue.main.async {
                    self.trustWritePending = false; self.rememberConnection.isEnabled = !self.trustReadPending; self.recoverConnection.isEnabled = !self.trustReadPending
                    do {
                        try result.get(); self.rememberedProfile = profile
                        #if !SENDER
                        self.renderDevices()
                        #endif
                        self.trustReadError = nil; self.recoverConnection.isHidden = true; self.recoverConnectionRow?.isHidden = true
                        self.trustExplanation.stringValue = "Conexión guardada · reconexión sin códigos al abrir las apps."
                        // A new authenticated session may have arrived while the
                        // write was pending; persist its latest endpoint too.
                        if self.sessionHasImage { self.rememberCurrentSession() }
                    }
                    catch { self.trustExplanation.stringValue = "No se guardó la conexión: \(error)"; self.rememberConnection.state = .off }
                }
            }
        } catch { trustExplanation.stringValue = "\(error)"; rememberConnection.state = .off }
    }
    @objc func restoreRememberedConnection() { readRememberedConnection(allowInteraction: true) }
    func readRememberedConnection(allowInteraction: Bool = false) {
        guard ReconnectPreference.enabled(account: trustAccount) else { return }
        // A role change can reuse a previously authorized in-memory profile.
        // Never expand access or change the Keychain item's policy.
        if let profile = rememberedProfile {
            guard !CommandLine.arguments.contains("--layout-preview") else { return }
            #if SENDER
            key.stringValue = profile.key; start()
            #else
            do { connect(try profile.link(), previouslyApproved: true) } catch { engine.reportStartFailure("\(error)") }
            #endif
            return
        }
        guard !trustReadPending, !trustWritePending else { return }
        let token = UUID(); trustRecovery = token; trustReadPending = true
        recoverConnection.isEnabled = false; rememberConnection.isEnabled = false
        trustExplanation.stringValue = allowInteraction ? "Esperando la autorización del Llavero. Completa la confirmación de macOS o cancélala." : "Recuperando la conexión guardada…"
        let request = loadRememberedConnection ?? { [trustStore] in try trustStore.load(allowInteraction: $0) }
        trustQueue.async { [weak self] in
            let result = Result { try request(allowInteraction) }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.trustReadPending = false; self.recoverConnection.isEnabled = true; self.rememberConnection.isEnabled = !self.trustWritePending
                guard self.trustRecovery == token else { return }
                self.trustRecovery = nil
                do {
                    guard let profile = try result.get() else {
                        self.trustExplanation.stringValue = "Primera conexión: pulsa el Mac disponible y confirma el código una sola vez."
                        self.recoverConnection.isHidden = true; self.recoverConnectionRow?.isHidden = true
                        return
                    }
                    let link = try profile.link()
                    self.rememberedProfile = profile; self.trustReadError = nil
                    #if !SENDER
                    self.renderDevices()
                    #endif
                    self.rememberConnection.state = .on
                    self.trustExplanation.stringValue = "Conexión recuperada. Se conserva en el Llavero de este Mac."
                    self.recoverConnection.isHidden = true
                    self.recoverConnectionRow?.isHidden = true
                    // Layout diagnostics inject the read and never start a stream.
                    if CommandLine.arguments.contains("--layout-preview") { return }
                    #if SENDER
                    self.key.stringValue = profile.key; self.start()
                    #else
                    self.connect(link, previouslyApproved: true)
                    #endif
                } catch {
                    let message = "\(error)"
                    // First try a silent Keychain read. Some macOS versions or
                    // renewed app signatures deny that read until the user has
                    // approved this app again. Retry once with normal Keychain
                    // interaction so a saved screen can reconnect on launch;
                    // if macOS still denies it, retain the explicit recovery UI.
                    if !allowInteraction && message.contains("El Llavero necesita autorización") {
                        self.trustRecovery = nil
                        self.readRememberedConnection(allowInteraction: true)
                        return
                    }
                    self.trustReadError = message; self.trustExplanation.stringValue = message
                    self.recoverConnection.isHidden = false; self.recoverConnectionRow?.isHidden = false
                }
            }
        }
    }
    func cancelTrustRecovery() {
        if trustRecovery != nil { trustExplanation.stringValue = "Recuperación cancelada. Puedes volver a intentarlo o conectar normalmente." }
        trustRecovery = nil
        recoverConnection.isEnabled = !trustReadPending && !trustWritePending; rememberConnection.isEnabled = !trustReadPending && !trustWritePending
    }
    @objc func toggleRemember() {
        if !CommandLine.arguments.contains("--layout-preview") { ReconnectPreference.save(rememberConnection.state == .on, account: trustAccount) }
        if rememberConnection.state == .on { rememberCurrentSession(); return }
        cancelTrustRecovery()
        guard !trustWritePending else { return }
        trustWritePending = true; rememberConnection.isEnabled = false; recoverConnection.isEnabled = false
        trustExplanation.stringValue = "Retirando la conexión guardada del Llavero…"
        sessionHasImage = false; currentSessionLink = nil
        stop()
        #if SENDER
        if let next = try? newPairingKey() { key.stringValue = next }
        #endif
        trustQueue.async { [weak self] in
            guard let self = self else { return }
            let result = Result { try self.trustStore.forget() }
            DispatchQueue.main.async {
                self.trustWritePending = false; self.rememberConnection.isEnabled = !self.trustReadPending; self.recoverConnection.isEnabled = !self.trustReadPending
                do {
                    try result.get(); self.rememberedProfile = nil
                    #if !SENDER
                    self.renderDevices()
                    #endif
                    self.trustReadError = nil; self.recoverConnection.isHidden = true; self.recoverConnectionRow?.isHidden = true
                    self.trustExplanation.stringValue = "Conexión olvidada. Para retirar el acceso, desmarca Recordar también en el otro Mac."
                } catch {
                    self.trustExplanation.stringValue = "No se pudo olvidar la conexión: \(error)"; self.rememberConnection.state = .on
                }
            }
        }
    }
    @objc func start() {
        cancelTrustRecovery()
        sessionHasImage = false
        do {
            #if SENDER
            engine.stop()
            engine.screenSlot = screenSlot
            engine.discoveryLabel = (Host.current().localizedName ?? "Este Mac") + " · Pantalla \(screenSlot + 1)"
            try engine.start(key: key.stringValue, options: selectedOptions(), rememberedService: rememberedProfile?.serviceName)
            #else
            guard endpoints.indices.contains(devices.indexOfSelectedItem) else { throw AireError("No aparece ningún Mac disponible. Abre la app del Mac que envía y comprueba que indica Disponible para conectar.") }
            let endpoint = endpoints[devices.indexOfSelectedItem]
            discoveryRetry?.cancel(); discoveryRetry = nil; discoveryGeneration = UUID()
            browser?.cancel(); browser = nil
            configurePairingCallbacks(); awaitingPairing = true
            engine.beginPairing(); displayPhase(.connecting); status.stringValue = "Solicitando conexión al otro Mac…"
            if let request = requestDeviceConnection { request(endpoint) }
            else { pairing.queue.async { self.pairing.start(endpoint: endpoint) } }
            #endif
        } catch { engine.reportStartFailure("\(error)") }
    }
    @objc func stop() {
        cancelTrustRecovery()
        #if !SENDER
        awaitingPairing = false; pairingAttempt = UUID()
        discoveryRetry?.cancel(); discoveryRetry = nil; discoveryGeneration = UUID()
        browser?.cancel(); browser = nil
        #endif
        engine.stop(); metrics.stringValue = ""; metrics.isHidden = true
        #if !SENDER
        pairing.queue.async { self.pairing.stop() }
        desktopBridge.stop(); video.releaseLocalButtons(); video.releaseKeyboard()
        presenter.clear(); cursorPresenter.clear(); video.clear(); viewer?.orderOut(nil)
        if !hosted || workspaceActive { browse() }
        #endif
    }
    @objc func about() {
        let alert = NSAlert(); alert.messageText = "PRISON DISPLAY v\(AppVersion.current)"; alert.informativeText = "La pantalla de un Mac, en otro Mac. Conexión local cifrada, pantalla ampliada o duplicada y ajustes en directo."; alert.runModal()
    }
    func confirmConnection(name: String, code: String, done: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            guard !self.hosted || self.workspaceActive else { done(false); return }
            NSApp.activate(ignoringOtherApps: true)
            self.cancelTrustRecovery()
            let alert = NSAlert(); alert.messageText = "Conectar con \(name)"
            alert.informativeText = "Código: \(code)\n\nComprueba que los dos Mac muestran el mismo código antes de aceptar."
            alert.addButton(withTitle: "Coincide: conectar"); alert.addButton(withTitle: "Cancelar")
            done(alert.runModal() == .alertFirstButtonReturn)
        }
    }
    #if SENDER
    func selectedOptions() -> StreamOptions {
        let sizes = [(1920, 1080), (1280, 720), (2560, 1440)]; let size = sizes[resolution.indexOfSelectedItem]
        return StreamOptions(extend: mode.indexOfSelectedItem == 0, width: size.0, height: size.1,
            fps: fps.indexOfSelectedItem == 0 ? 60 : 30,
            bitrate: VideoQualityProfile.all[quality.indexOfSelectedItem].ceiling, nativeCursor: cursorStyle.indexOfSelectedItem == 1)
    }
    @objc func allowMouse() {
        let allowed = AXIsProcessTrusted()
        updateInputState()
        if !allowed, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    @objc func settingsChanged() {
        var saved = DisplayPreferences(screenSlot: screenSlot); saved.mode = mode.indexOfSelectedItem
        saved.resolution = resolution.indexOfSelectedItem; saved.fps = fps.indexOfSelectedItem; saved.quality = quality.indexOfSelectedItem; saved.cursor = cursorStyle.indexOfSelectedItem
        saved.save(screenSlot: screenSlot)
        settingsState.stringValue = currentPhase == .streaming || currentPhase == .applying ? "Aplicando los ajustes seleccionados…" : "Ajustes guardados · se aplicarán al conectar"
        engine.update(options: selectedOptions())
    }
    @objc func copyConnectionLink() {
        guard let link = connectionLink else { status.stringValue = "Inicia la conexión para crear el enlace."; return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
        status.stringValue = "Enlace copiado. Pégalo en PRISON DISPLAY del otro Mac. El enlace permite conectarse: compártelo solo con tu otro Mac."
    }
    @objc func openDisplays() { if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") { NSWorkspace.shared.open(url) } }
    #else
    func saveInputPreferences() {
        guard !CommandLine.arguments.contains("--layout-preview") else { return }
        var saved = ReceiverPreferences()
        saved.keyboard = keyboardSwitch.state == .on; saved.crossing = desktopToggle.state == .on
        saved.edge = desktopEdge.indexOfSelectedItem; saved.save()
    }
    @objc func toggleDesktop(_ sender: NSButton) {
        if sender.state == .off {
            desktopBridge.stop(); desktopStatus.stringValue = "Desactivado. Control en este Mac."
            saveInputPreferences(); return
        }
        do { try desktopBridge.start(); saveInputPreferences() }
        catch { sender.state = .off; desktopStatus.stringValue = "\(error)" }
    }
    @objc func changeDesktopEdge() {
        desktopBridge.leave(); desktopBridge.edge = DesktopEdge(rawValue: desktopEdge.indexOfSelectedItem) ?? .right
        saveInputPreferences()
    }
    @objc func openDesktopPermission() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    @objc func toggleKeyboard(_ sender: NSButton) { video.keyboardEnabled = sender.state == .on; saveInputPreferences(); updateInputState() }
    private func configurePairingCallbacks() {
        let attempt = UUID(); pairingAttempt = attempt
        pairing.onConfirm = { [weak self] name, code, done in DispatchQueue.main.async {
            guard let self = self, self.pairingAttempt == attempt, self.awaitingPairing, !self.hosted || self.workspaceActive else { done(false); return }
            self.confirmConnection(name: name, code: code, done: done)
        } }
        pairing.onStatus = { [weak self] text in DispatchQueue.main.async {
            guard let self = self, self.pairingAttempt == attempt, self.awaitingPairing else { return }
            self.status.stringValue = text
        } }
        pairing.onConnected = { [weak self] link in DispatchQueue.main.async {
            guard let self = self, self.pairingAttempt == attempt, self.awaitingPairing, !self.hosted || self.workspaceActive else { return }
            self.awaitingPairing = false; self.connect(link)
        } }
        pairing.onEnded = { [weak self] in DispatchQueue.main.async {
            guard let self = self, self.pairingAttempt == attempt, self.awaitingPairing, !self.hosted || self.workspaceActive else { return }
            self.awaitingPairing = false; self.engine.reportStartFailure(self.status.stringValue)
            if !CommandLine.arguments.contains("--layout-preview") { self.browse() }
        } }
    }
    // Buttons resolve the current endpoint at click time: disappeared or reordered
    // Bonjour results can never send a request to a different computer.
    func renderDevices() {
        for view in deviceList.arrangedSubviews { deviceList.removeArrangedSubview(view); view.removeFromSuperview() }
        deviceActions.removeAll()
        let ready = currentPhase == .idle || currentPhase == .failed || currentPhase == .available
        if let profile = rememberedProfile {
            let label = NSTextField(wrappingLabelWithString: savedDeviceName + " · Enlazado")
            label.font = .systemFont(ofSize: 14, weight: .semibold)
            deviceList.addArrangedSubview(label); label.widthAnchor.constraint(equalTo: deviceList.widthAnchor).isActive = true
            let button = PrisonActionButton(title: ready ? "Reconectar" : (sessionHasImage ? "Conectado" : "Reconectando…"), target: self, action: #selector(connectSavedDevice))
            button.isEnabled = ready; button.toolTip = "Recupera la conexión ya autorizada con " + profile.host
            button.widthAnchor.constraint(equalToConstant: 150).isActive = true
            deviceList.addArrangedSubview(button); deviceActions.append(button)
        }
        for (index, endpoint) in endpoints.enumerated() {
            guard case .service(let name, _, _, _) = endpoint else { continue }
            let row = NSStackView(); row.orientation = .horizontal; row.spacing = 12; row.alignment = .centerY
            let label = NSTextField(wrappingLabelWithString: name + "\nDisponible en tu red")
            label.font = .systemFont(ofSize: 14); label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let button = PrisonActionButton(title: "Conectar", target: self, action: #selector(connectDevice(_:)))
            // Retired buttons are rejected after every discovery refresh.
            button.identifier = NSUserInterfaceItemIdentifier("device.\(index)")
            button.toolTip = name; button.tag = index; button.isEnabled = ready
            row.addArrangedSubview(label); row.addArrangedSubview(button)
            label.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -122).isActive = true
            button.widthAnchor.constraint(equalToConstant: 110).isActive = true
            deviceList.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: deviceList.widthAnchor).isActive = true
            deviceActions.append(button)
        }
        if endpoints.isEmpty && (rememberedProfile == nil || ready) {
            let message = NSTextField(wrappingLabelWithString: sessionHasImage ? "La pantalla está conectada." : discoveryMessage ?? (searching ? "Buscando Mac en tu red…" : "No hay Mac disponibles. Abre PRISON DISPLAY en el otro equipo y elige Enviar pantalla."))
            message.font = .systemFont(ofSize: 13); message.textColor = prisonSecondaryText
            deviceList.addArrangedSubview(message); message.widthAnchor.constraint(equalTo: deviceList.widthAnchor).isActive = true
        }
        for button in deviceActions { button.bezelStyle = .rounded; button.heightAnchor.constraint(equalToConstant: 38).isActive = true }
    }
    @objc func connectDevice(_ button: NSButton) {
        guard deviceActions.contains(where: { $0 === button }), endpoints.indices.contains(button.tag), button.isEnabled else { return }
        devices.selectItem(at: button.tag); start()
    }
    @objc func connectSavedDevice() {
        guard let profile = rememberedProfile else { return }
        do { connect(try profile.link(), previouslyApproved: true) }
        catch { engine.reportStartFailure("\(error)") }
    }
    func updateDiscoveredDevices(_ results: [NWEndpoint]) {
        let selected = endpoints.indices.contains(devices.indexOfSelectedItem) ? endpoints[devices.indexOfSelectedItem] : nil
        endpoints = Array(Set(results)).filter { if case .service = $0 { return true }; return false }.sorted { "\($0)" < "\($1)" }
        devices.removeAllItems()
        for endpoint in endpoints { if case .service(let name, _, _, _) = endpoint { devices.addItem(withTitle: name) } }
        if endpoints.isEmpty { devices.addItem(withTitle: "Ningún Mac disponible") }
        else if let selected = selected, let index = endpoints.firstIndex(of: selected) { devices.selectItem(at: index) }
        searching = false; discoveryMessage = nil; updateConnectionActions()
    }
    func browse() {
        guard browser == nil, !hosted || workspaceActive, !CommandLine.arguments.contains("--layout-preview") || startDiscovery != nil else { return }
        discoveryRetry?.cancel(); discoveryRetry = nil
        let token = UUID(); discoveryGeneration = token; searching = true; discoveryMessage = nil; renderDevices()
        let b = NWBrowser(for: .bonjour(type: PairingServer.service, domain: nil), using: discoveryParameters()); browser = b
        b.browseResultsChangedHandler = { [weak self, weak b] results, _ in DispatchQueue.main.async {
            guard let self = self, self.browser === b else { return }
            self.updateDiscoveredDevices(results.map { $0.endpoint })
        }}
        b.stateUpdateHandler = { [weak self, weak b] state in DispatchQueue.main.async {
            guard let self = self, self.browser === b else { return }
            if #available(macOS 11.0, *), case .waiting = state {
                self.updateDiscoveredDevices([])
                self.discoveryMessage = "Esperando a la red. Comprueba Wi-Fi y el permiso Red local en este Mac."
                self.renderDevices()
            }
            if case .failed = state {
                b?.cancel(); self.browser = nil; self.updateDiscoveredDevices([])
                self.status.stringValue = "No se pudo buscar en la red. Comprueba Red local; volveremos a intentarlo."
                let retry = DispatchWorkItem { [weak self] in
                    guard let self = self, self.discoveryGeneration == token, !self.hosted || self.workspaceActive else { return }
                    self.browse()
                }
                self.discoveryRetry = retry; DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, self.discoveryRetryDelay), execute: retry)
            }
        }}
        if let start = startDiscovery { start(b) } else { b.start(queue: engine.queue) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self, weak b] in
            guard let self = self, self.browser === b, self.searching else { return }
            self.searching = false; self.renderDevices()
        }
    }
    @objc func pasteConnectionLink() {
        do {
            guard let text = NSPasteboard.general.string(forType: .string), let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw AireError("Copia el enlace en el Mac que envía antes de pegarlo.") }
            connect(try ConnectionLink(url))
        } catch { status.stringValue = "\(error)" }
    }
    func connect(_ link: ConnectionLink, previouslyApproved: Bool = false) {
        guard !hosted || workspaceActive else { return }
        awaitingPairing = false; pairingAttempt = UUID()
        cancelTrustRecovery()
        discoveryRetry?.cancel(); discoveryRetry = nil; discoveryGeneration = UUID()
        browser?.cancel(); browser = nil
        currentSessionLink = link; sessionHasImage = false; connectedPeerName = nil
        do { try engine.connect(endpoint: link.endpoint, key: link.key, fallback: previouslyApproved || link.serviceName == nil ? nil : link.hostEndpoint, previouslyApproved: previouslyApproved); showViewer() }
        catch { status.stringValue = "\(error)" }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        do { connect(try ConnectionLink(url)) } catch { status.stringValue = "\(error)" }
    }
    func showViewer() {
        if viewer == nil {
            let w = PrisonViewerWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Pantalla recibida · PRISON DISPLAY v\(AppVersion.current)"; w.isReleasedWhenClosed = false
            w.contentView = video; w.collectionBehavior = [.fullScreenPrimary]; w.center(); w.setFrameAutosaveName("PrisonDisplay.viewer"); viewer = w; w.delegate = self
        }
        viewer?.makeKeyAndOrderFront(nil)
    }
    @objc func fullscreen() {
        guard sessionHasImage else {
            status.stringValue = "Conecta un Mac para abrir su pantalla a pantalla completa."
            return
        }
        showViewer(); viewer?.toggleFullScreen(nil)
    }
    private func enterViewerFullscreen() {
        guard sessionHasImage, !hosted || workspaceActive else { return }
        showViewer()
        if viewer?.styleMask.contains(.fullScreen) != true { viewer?.toggleFullScreen(nil) }
        status.stringValue = "Pantalla completa activada desde el Mac principal."
    }
    #endif
    func windowDidEnterFullScreen(_ notification: Notification) {
        #if !SENDER
        if (notification.object as? NSWindow) === viewer { video.setFullscreenPresentation(true) }
        #endif
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        #if !SENDER
        if (notification.object as? NSWindow) === viewer { video.setFullscreenPresentation(false) }
        #endif
    }
    func windowDidResignKey(_ notification: Notification) {
        #if !SENDER
        if (notification.object as? NSWindow) === viewer { video.releaseLocalButtons(); video.releaseKeyboard() }
        #endif
    }
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === window { engine.stop(); NSApp.terminate(nil) }
        #if !SENDER
        if (notification.object as? NSWindow) === viewer { stop() }
        #endif
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        #if !SENDER
        desktopBridge.applicationDidBecomeActive()
        #endif
    }
    // Restore Quartz association before the app loses foreground ownership.
    func applicationWillResignActive(_ notification: Notification) {
        #if !SENDER
        desktopBridge.applicationDidResignActive()
        #endif
    }
    func applicationWillTerminate(_ notification: Notification) {
        cancelTrustRecovery(); permissionTimer?.invalidate()
        #if SENDER
        engine.releasePointerBeforeExit()
        #else
        desktopBridge.stop()
        #endif
        engine.stop()
    }
}

#endif // !UNIFIED
