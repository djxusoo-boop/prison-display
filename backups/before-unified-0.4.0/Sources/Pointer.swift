import AppKit
import CoreGraphics

// Cursor permission is part of its live payload. Refresh it without querying
// Security on every 8 ms sample; the injectors still enforce permission live.
final class CursorPermission {
    private let read: () -> Bool
    private let lock = NSLock()
    private var checked: UInt64?
    private var allowed = false
    init(read: @escaping () -> Bool) { self.read = read }
    func value(now: UInt64 = monotonicNS()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if checked == nil || now < checked! || now - checked! >= 500_000_000 {
            allowed = read(); checked = now
        }
        return allowed
    }
}

// The display server may pause while answering geometry queries. Cache them
// outside the mouse hot path and invalidate on every display reconfiguration.
final class DisplayGeometry {
    static let shared = DisplayGeometry()
    private let lock = NSLock()
    private var values: [CGDirectDisplayID: CGRect] = [:]
    private var generation: UInt64 = 0
    private let query: (CGDirectDisplayID) -> CGRect
    private let watchesDisplays: Bool
    private var hasObserver = false
    init(watchesDisplays: Bool = true, query: @escaping (CGDirectDisplayID) -> CGRect = CGDisplayBounds) {
        self.query = query; self.watchesDisplays = watchesDisplays
        if watchesDisplays {
            hasObserver = CGDisplayRegisterReconfigurationCallback(DisplayGeometry.changed, Unmanaged.passUnretained(self).toOpaque()) == .success
        }
    }
    private static let changed: CGDisplayReconfigurationCallBack = { _, _, context in
        guard let context = context else { return }
        Unmanaged<DisplayGeometry>.fromOpaque(context).takeUnretainedValue().invalidate()
    }
    func invalidate() { lock.lock(); generation &+= 1; values.removeAll(keepingCapacity: true); lock.unlock() }
    func bounds(_ display: CGDirectDisplayID) -> CGRect {
        lock.lock()
        if let value = values[display] { lock.unlock(); return value }
        let epoch = generation; lock.unlock()
        let value = query(display)
        lock.lock()
        if generation == epoch, hasObserver || !watchesDisplays, !value.isEmpty { values[display] = value }
        lock.unlock()
        return value
    }
    deinit {
        if hasObserver { CGDisplayRemoveReconfigurationCallback(DisplayGeometry.changed, Unmanaged.passUnretained(self).toOpaque()) }
    }
}

let inputFlags = CGEventFlags.maskShift.union(.maskControl).union(.maskAlternate).union(.maskCommand).union(.maskAlphaShift).union(.maskSecondaryFn).union(.maskNumericPad).rawValue

struct KeyboardMessage: Equatable {
    enum Action: UInt8 { case down, up, modifiers, releaseAll }
    let action: Action
    let keyCode: UInt16
    let flags: UInt64
    let repeated: Bool
    init(action: Action, keyCode: UInt16 = 0, flags: UInt64 = 0, repeated: Bool = false) {
        self.action = action; self.keyCode = keyCode; self.flags = flags & inputFlags; self.repeated = repeated
    }
    init(_ data: Data) throws {
        guard data.count == 12, let action = Action(rawValue: data.first!) else { throw AireError("Tecla inválida.") }
        var r = Reader(data.dropFirst()); keyCode = try r.u16(); flags = try r.u64(); let repeatByte = try r.bytes(1).first!
        guard keyCode <= 127, flags & ~inputFlags == 0, repeatByte <= 1,
              action != .releaseAll || (keyCode == 0 && flags == 0 && repeatByte == 0) else { throw AireError("Tecla inválida.") }
        self.action = action; repeated = repeatByte == 1
    }
    func serialize() -> Data { var d = Data([action.rawValue]); d.u16(keyCode); d.u64(flags); d.append(repeated ? 1 : 0); return d }
}

// Coordinates are normalized to the captured image, independent of window size.
struct PointerMessage: Equatable {
    enum Action: UInt8 { case move = 0, leftDown, leftUp, rightDown, rightUp, scroll }
    let action: Action
    let x: Double
    let y: Double
    let delta: Double
    let clicks: Int
    let deltaX: Double
    let flags: UInt64
    static let encodedSize = Wire.pointerSize
    init(action: Action, x: Double, y: Double, delta: Double = 0, clicks: Int = 1, deltaX: Double = 0, flags: UInt64 = 0) {
        self.action = action; self.x = x; self.y = y; self.delta = delta; self.clicks = clicks; self.deltaX = deltaX; self.flags = flags & inputFlags
    }
    init(_ data: Data) throws {
        guard data.count == Self.encodedSize, let action = Action(rawValue: data.first!) else { throw AireError("Evento de ratón inválido.") }
        var r = Reader(data.dropFirst()); x = Double(bitPattern: try r.u64()); y = Double(bitPattern: try r.u64()); delta = Double(bitPattern: try r.u64()); clicks = Int(try r.bytes(1).first!)
        deltaX = Double(bitPattern: try r.u64()); flags = try r.u64()
        self.action = action
        guard deltaX.isFinite, abs(deltaX) <= 120, flags & ~inputFlags == 0, x.isFinite, y.isFinite, delta.isFinite, (0...1).contains(x), (0...1).contains(y), abs(delta) <= 120, (1...3).contains(clicks) else { throw AireError("Coordenadas de ratón inválidas.") }
    }
    func serialize() -> Data {
        var d = Data([action.rawValue]); d.u64(x.bitPattern); d.u64(y.bitPattern); d.u64(delta.bitPattern); d.append(UInt8(clicks)); d.u64(deltaX.bitPattern); d.u64(flags); return d
    }
    func point(in rect: CGRect) -> CGPoint { CGPoint(x: rect.minX + x * max(0, rect.width - 1), y: rect.minY + y * max(0, rect.height - 1)) }
    static func normalized(_ point: CGPoint, in rect: CGRect) -> CGPoint? {
        guard rect.width > 0, rect.height > 0, rect.contains(point) else { return nil }
        return CGPoint(x: (point.x - rect.minX) / rect.width, y: (point.y - rect.minY) / rect.height)
    }
}

#if SENDER
final class KeyboardInjector {
    var trusted: () -> Bool = { AXIsProcessTrusted() }
    var post: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }
    private var held = Set<UInt16>()
    private var modifiers = Set<UInt16>()
    func receive(_ message: KeyboardMessage) {
        if message.action == .releaseAll { releaseKeys(); return }
        guard trusted() else { return }
        var down = message.action == .down
        if message.action == .modifiers {
            let masks: [UInt16: CGEventFlags] = [56: .maskShift, 60: .maskShift, 59: .maskControl, 62: .maskControl, 58: .maskAlternate, 61: .maskAlternate, 55: .maskCommand, 54: .maskCommand, 57: .maskAlphaShift, 63: .maskSecondaryFn]
            guard let mask = masks[message.keyCode] else { return }
            down = message.flags & mask.rawValue != 0 && !held.contains(message.keyCode)
            modifiers.insert(message.keyCode)
        }
        if down { held.insert(message.keyCode) } else { guard held.remove(message.keyCode) != nil else { return } }
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: message.keyCode, keyDown: down) else { return }
        event.flags = CGEventFlags(rawValue: message.flags)
        if message.action == .modifiers { event.type = .flagsChanged }
        event.setIntegerValueField(.keyboardEventAutorepeat, value: message.repeated ? 1 : 0)
        post(event)
    }
    func releaseKeys() {
        if trusted() {
            for code in held.sorted() {
                if let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) { event.flags = []; if modifiers.contains(code) { event.type = .flagsChanged }; post(event) }
            }
        }
        held.removeAll(); modifiers.removeAll()
    }
}
final class PointerInjector {
    var trusted: () -> Bool = { AXIsProcessTrusted() }
    var displayID: CGDirectDisplayID = 0
    var desktopDisplayID: CGDirectDisplayID?
    private var left = false
    private var right = false
    private var position = CGPoint.zero
    // Tests inspect generated events without posting input to the user's desktop.
    var post: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }
    func receive(_ message: PointerMessage) {
        let target = desktopDisplayID ?? displayID
        guard target != 0, trusted() else { return }
        position = message.point(in: DisplayGeometry.shared.bounds(target))
        let type: CGEventType
        let button: CGMouseButton
        switch message.action {
        case .move: type = left ? .leftMouseDragged : (right ? .rightMouseDragged : .mouseMoved); button = right ? .right : .left
        case .leftDown: left = true; type = .leftMouseDown; button = .left
        case .leftUp: left = false; type = .leftMouseUp; button = .left
        case .rightDown: right = true; type = .rightMouseDown; button = .right
        case .rightUp: right = false; type = .rightMouseUp; button = .right
        case .scroll:
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(message.delta.rounded()), wheel2: Int32(message.deltaX.rounded()), wheel3: 0) else { return }
            event.location = position; event.flags = CGEventFlags(rawValue: message.flags); post(event); return
        }
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: position, mouseButton: button) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(message.clicks)); event.flags = CGEventFlags(rawValue: message.flags); post(event)
    }
    func releaseButtons() {
        if trusted() {
            for (held, type, button) in [(left, CGEventType.leftMouseUp, CGMouseButton.left), (right, .rightMouseUp, .right)] where held {
                if let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: position, mouseButton: button) { post(event) }
            }
        }
        left = false; right = false
    }
}
#endif
