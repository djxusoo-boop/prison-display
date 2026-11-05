import AppKit
import CoreGraphics
import Carbon

// A desktop has one physical pointer and keyboard. Multiple screen sessions
// may coexist, but only one receiver may own the main desktop at a time.
final class DesktopInputOwnership {
    static let shared = DesktopInputOwnership()
    private let lock = NSLock()
    private var owner: UUID?
    func acquire(_ candidate: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard owner == nil || owner == candidate else { return false }
        owner = candidate; return true
    }
    func release(_ candidate: UUID) {
        lock.lock(); defer { lock.unlock() }
        if owner == candidate { owner = nil }
    }
}

// A separate, authenticated lease prevents stale input from changing displays.
struct DesktopControlMessage {
    enum Action: UInt8 { case begin, end, heartbeat, accepted, rejected }
    let action: Action
    let token: UInt64
    var width: UInt32 = 0
    var height: UInt32 = 0
    init(action: Action, token: UInt64, width: UInt32 = 0, height: UInt32 = 0) {
        self.action = action; self.token = token; self.width = width; self.height = height
    }
    init(_ data: Data) throws {
        guard data.count == 17, let action = Action(rawValue: data.first!) else { throw AireError("Control de escritorio inválido.") }
        var r = Reader(data.dropFirst()); token = try r.u64(); width = try r.u32(); height = try r.u32(); self.action = action
        guard token != 0, action == .accepted ? ((4...32768).contains(width) && (4...32768).contains(height)) : (width == 0 && height == 0) else { throw AireError("Control de escritorio inválido.") }
    }
    func serialize() -> Data { var d = Data([action.rawValue]); d.u64(token); d.u32(width); d.u32(height); return d }
}

enum DesktopEdge: Int, CaseIterable {
    case right, left, above, below
    var title: String { ["A la derecha de este Mac", "A la izquierda de este Mac", "Encima de este Mac", "Debajo de este Mac"][rawValue] }
    func crossing(point: CGPoint, delta: CGPoint, bounds: CGRect) -> Bool {
        guard bounds.width > 4, bounds.height > 4 else { return false }
        switch self {
        case .right: return point.x >= bounds.maxX-2 && delta.x > 0
        case .left: return point.x <= bounds.minX+1 && delta.x < 0
        case .above: return point.y <= bounds.minY+1 && delta.y < 0
        case .below: return point.y >= bounds.maxY-2 && delta.y > 0
        }
    }
    func entry(point: CGPoint, bounds: CGRect, remote: CGSize) -> CGPoint {
        let x = min(1, max(0, (point.x-bounds.minX)/bounds.width))
        let y = min(1, max(0, (point.y-bounds.minY)/bounds.height))
        switch self {
        case .right: return CGPoint(x: 2, y: y*(remote.height-1))
        case .left: return CGPoint(x: remote.width-3, y: y*(remote.height-1))
        case .above: return CGPoint(x: x*(remote.width-1), y: remote.height-3)
        case .below: return CGPoint(x: x*(remote.width-1), y: 2)
        }
    }
    func returning(_ point: CGPoint, remote: CGSize) -> Bool {
        switch self {
        case .right: return point.x < 0
        case .left: return point.x >= remote.width
        case .above: return point.y >= remote.height
        case .below: return point.y < 0
        }
    }
}

#if !SENDER || UNIFIED
// Cursor ownership is main-thread only and balanced across every lease. AppKit
// preserves the hide when cursor rectangles change; physical deltas still arrive
// while Quartz disconnects the local pointer from the mouse.
final class LocalCursorLease {
    var isForeground: () -> Bool = { NSApp.isActive }
    var associate: (Bool) -> CGError = { CGAssociateMouseAndMouseCursorPosition($0 ? 1 : 0) }
    var visibility: (Bool) -> Void = { if $0 { NSCursor.hide() } else { NSCursor.unhide() } }
    private(set) var detached = false
    private(set) var hidden = false
    func acquire() -> Bool {
        guard isForeground() else { return false }
        if !detached {
            guard associate(false) == .success else { return false }
            detached = true
        }
        if !hidden { visibility(true); hidden = true }
        return true
    }
    @discardableResult func release() -> Bool {
        if detached, associate(true) == .success { detached = false }
        if hidden { visibility(false); hidden = false }
        return !detached
    }
    deinit { release() }
}
// Runs only on the main run loop, opt-in, and only suppresses input after ACK.
// Idle events never leave the iMac. Tests replace all system side effects.
final class DesktopBridge {
    var mouseEnabled = true { didSet { if !mouseEnabled { leave() } } }
    var keyboardEnabled = true { didSet { if !keyboardEnabled && oldValue && remote { sendKeyboard(KeyboardMessage(action: .releaseAll)) } } }
    var edge = DesktopEdge.right
    var connected = false { didSet {
        if !connected { leave() }
        if tap != nil {
            onStatus(connected ? "Cruce preparado. Lleva el ratón al borde elegido. ⌃⌥Esc devuelve el control a este Mac." : "Cruce activado · esperando conexión. El control sigue en este Mac.")
        }
    } }
    var sendControl: (DesktopControlMessage) -> Void = { _ in }
    var sendPointer: (PointerMessage) -> Void = { _ in }
    var sendKeyboard: (KeyboardMessage) -> Void = { _ in }
    var onStatus: (String) -> Void = { _ in }
    var onDisabled: () -> Void = { }
    var onControlChanged: (Bool) -> Void = { _ in }
    let cursor = LocalCursorLease()
    var bounds: () -> CGRect = { DisplayGeometry.shared.bounds(CGMainDisplayID()) }
    var now: () -> UInt64 = { monotonicNS() }
    var protectedInput: () -> Bool = { IsSecureEventInputEnabled() }
    var buttonHeld: () -> Bool = { CGEventSource.buttonState(.combinedSessionState, button: .left) || CGEventSource.buttonState(.combinedSessionState, button: .right) }
    var warp: (CGPoint) -> Void = { _ = CGWarpMouseCursorPosition($0) }
    var hide: (Bool) -> Void { get { cursor.visibility } set { cursor.visibility = newValue } }
    private(set) var token: UInt64 = 0
    private(set) var remote = false
    private var requested = false
    private var activationPending = false
    private var activationStarted: UInt64 = 0
    private var anchor = CGPoint.zero
    private var position = CGPoint.zero
    private var size = CGSize.zero
    private var received: UInt64 = 0
    private var cooldown: UInt64 = 0
    private var left = false, right = false
    private var localKeys = Set<UInt16>()
    private var previousApp: NSRunningApplication?
    var focus: ((Bool) -> Void)?
    private func focusDesktop(_ entering: Bool) {
        if let focus = focus { focus(entering); return }
        if entering {
            previousApp = NSWorkspace.shared.frontmostApplication
            NSApp.activate(ignoringOtherApps: true)
        } else {
            if previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp?.activate(options: [.activateIgnoringOtherApps]) }
            previousApp = nil
        }
    }
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    var isActive: Bool { tap != nil }
    func start() throws {
        guard mouseEnabled else { onStatus("Ratón compartido desactivado. El control sigue en este Mac."); return }
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else { throw AireError("Para cruzar entre escritorios, activa PRISON DISPLAY en Privacidad → Accesibilidad. Después vuelve a marcar esta opción.") }
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .otherMouseDragged, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .scrollWheel, .keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context = context else { return Unmanaged.passUnretained(event) }
            let bridge = Unmanaged<DesktopBridge>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { bridge.stop(); bridge.onDisabled(); bridge.onStatus("Cruce desactivado por macOS. Control devuelto a este Mac. Vuelve a marcar la opción para reanudarlo."); return Unmanaged.passUnretained(event) }
            return bridge.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { throw AireError("macOS no permite controlar el ratón y teclado. Comprueba Accesibilidad de PRISON DISPLAY; si lo solicita, permite también Monitorización de entrada.") }
        guard let s = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0) else { CFMachPortInvalidate(t); throw AireError("No se pudo iniciar el cruce de escritorio.") }
        tap = t; source = s; CFRunLoopAddSource(CFRunLoopGetMain(), s, .commonModes); CGEvent.tapEnable(tap: t, enable: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        if let timer = timer { RunLoop.main.add(timer, forMode: .common) }
        onStatus(connected ? "Cruce preparado. Lleva el ratón al borde elegido. ⌃⌥Esc devuelve el control a este Mac." : "Cruce activado · esperando conexión. El control sigue en este Mac.")
    }
    func stop() {
        leave(); localKeys.removeAll(); timer?.invalidate(); timer = nil
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }
    func tick() {
        if !remote && cursor.detached { cursor.release() }
        guard requested || activationPending || remote else { return }
        if protectedInput() { leave(); onStatus("Control devuelto a este Mac: entrada protegida activa."); return }
        if now() - received > 2_000_000_000 { leave(); onStatus("El otro Mac dejó de responder. Control devuelto a este Mac."); return }
        if activationPending {
            if now() - activationStarted >= 1_000_000_000 {
                leave(); onStatus("No se pudo activar el cruce. Control conservado en este Mac."); return
            }
            finishActivation()
        }
        if remote {
            guard cursor.isForeground() else { applicationDidResignActive(); return }
            sendControl(DesktopControlMessage(action: .heartbeat, token: token))
        }
    }
    func reply(_ message: DesktopControlMessage) {
        guard message.token == token, requested || activationPending || remote else { return }
        if message.action == .rejected { leave(); onStatus("El otro Mac no permite el control. Comprueba su permiso de Accesibilidad."); return }
        guard message.action == .accepted else { return }
        received = now()
        guard requested else { return }
        requested = false; activationPending = true; activationStarted = now()
        size = CGSize(width: Int(message.width), height: Int(message.height))
        position = edge.entry(point: anchor, bounds: bounds(), remote: size)
        focusDesktop(true); finishActivation()
    }
    func applicationDidBecomeActive() { finishActivation(); if !remote { cursor.release() } }
    func applicationDidResignActive() {
        if remote || activationPending {
            leave(restoreFocus: false)
            onStatus("Control devuelto a este Mac al cambiar de aplicación.")
        } else { cursor.release() }
    }
    private func finishActivation() {
        guard activationPending, cursor.isForeground() else { return }
        guard connected, !protectedInput(), now() - received <= 2_000_000_000,
              now() - activationStarted < 1_000_000_000 else { leave(); return }
        guard cursor.acquire() else {
            leave(); onStatus("macOS no permitió ocultar el cursor local. Control conservado en este Mac."); return
        }
        activationPending = false; remote = true; onControlChanged(true); sendPosition(.move)
        onStatus("Controlando el otro Mac · cursor oculto en este Mac. Regresa por el mismo borde o pulsa ⌃⌥Esc.")
    }
    func leave(restoreFocus: Bool = true) {
        let wasRemote = remote, wasRequested = requested, wasPending = activationPending
        if wasRemote {
            if left { sendPosition(.leftUp) }; if right { sendPosition(.rightUp) }
            sendKeyboard(KeyboardMessage(action: .releaseAll))
        }
        remote = false; requested = false; activationPending = false; left = false; right = false
        if wasRemote || wasRequested || wasPending { sendControl(DesktopControlMessage(action: .end, token: token)); cooldown = now()+500_000_000 }
        if wasRemote {
            let b = bounds()
            let x = min(1, max(0, position.x/max(1, size.width-1)))
            let y = min(1, max(0, position.y/max(1, size.height-1)))
            var home = anchor
            switch edge {
            case .right: home = CGPoint(x: b.maxX-3, y: b.minY+y*b.height)
            case .left: home = CGPoint(x: b.minX+2, y: b.minY+y*b.height)
            case .above: home = CGPoint(x: b.minX+x*b.width, y: b.minY+2)
            case .below: home = CGPoint(x: b.minX+x*b.width, y: b.maxY-3)
            }
            warp(CGPoint(x: min(b.maxX-3, max(b.minX+2, home.x)), y: min(b.maxY-3, max(b.minY+2, home.y))))
        }
        cursor.release()
        if wasRemote { onControlChanged(false) }
        if wasRemote || wasPending {
            if restoreFocus { focusDesktop(false) } else { previousApp = nil }
        }
    }
    private func sendPosition(_ action: PointerMessage.Action, event: CGEvent? = nil) {
        sendPointer(PointerMessage(action: action, x: Double(position.x/max(1, size.width-1)), y: Double(position.y/max(1, size.height-1)), delta: action == .scroll ? max(-120, min(120, event?.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) ?? 0)) : 0, clicks: max(1, min(3, Int(event?.getIntegerValueField(.mouseEventClickState) ?? 1))), deltaX: action == .scroll ? max(-120, min(120, event?.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) ?? 0)) : 0, flags: keyboardEnabled ? (event?.flags.rawValue ?? 0) : 0))
    }
    private func applyMouseDelta(_ event: CGEvent) {
        let x = event.getDoubleValueField(.mouseEventDeltaX), y = event.getDoubleValueField(.mouseEventDeltaY)
        guard x.isFinite, y.isFinite else { return }
        position.x = min(size.width-1, max(0, position.x+x))
        position.y = min(size.height-1, max(0, position.y+y))
    }
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if !mouseEnabled || !connected || protectedInput() { leave(); return false }
        let movement = [.mouseMoved, .leftMouseDragged, .rightMouseDragged].contains(type)
        let delta = CGPoint(x: event.getDoubleValueField(.mouseEventDeltaX), y: event.getDoubleValueField(.mouseEventDeltaY))
        if !remote {
            if requested || activationPending, type != .mouseMoved || !edge.crossing(point: event.location, delta: delta, bounds: bounds()) { leave() }
            let localCode = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
            if type == .keyDown { localKeys.insert(localCode) }
            if type == .keyUp { localKeys.remove(localCode) }
            // Never transfer an existing drag, modifier or held key to another Mac.
            if !requested, !activationPending, !cursor.detached, localKeys.isEmpty, type == .mouseMoved, now() >= cooldown, event.flags.intersection([.maskShift, .maskCommand, .maskControl, .maskAlternate]).isEmpty,
               !buttonHeld(),
               edge.crossing(point: event.location, delta: delta, bounds: bounds()) {
                anchor = event.location; token = max(token+1, now()); received = now(); requested = true
                sendControl(DesktopControlMessage(action: .begin, token: token))
            }
            return false
        }
        let code = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyDown, code == 53, event.flags.contains([.maskControl, .maskAlternate]) { leave(); onStatus("Control devuelto a este Mac."); return true }
        if movement {
            position.x += delta.x; position.y += delta.y
            if !left && !right && edge.returning(position, remote: size) { leave(); onStatus("Control devuelto a este Mac."); return true }
            position.x = min(size.width-1, max(0, position.x)); position.y = min(size.height-1, max(0, position.y)); sendPosition(.move, event: event)
        } else if type == .keyDown || type == .keyUp || type == .flagsChanged {
            guard keyboardEnabled else { return false }
            sendKeyboard(KeyboardMessage(action: type == .keyDown ? .down : (type == .keyUp ? .up : .modifiers), keyCode: code, flags: event.flags.rawValue, repeated: event.getIntegerValueField(.keyboardEventAutorepeat) != 0))
        } else {
            let action: PointerMessage.Action
            switch type {
            case .leftMouseDown: applyMouseDelta(event); left = true; action = .leftDown
            case .leftMouseUp: applyMouseDelta(event); left = false; action = .leftUp
            case .rightMouseDown: applyMouseDelta(event); right = true; action = .rightDown
            case .rightMouseUp: applyMouseDelta(event); right = false; action = .rightUp
            case .scrollWheel: action = .scroll
            default: leave(); return false
            }
            sendPosition(action, event: event)
        }
        return true
    }
    deinit { cursor.release(); timer?.invalidate(); if let tap = tap { CFMachPortInvalidate(tap) } }
}
#endif
