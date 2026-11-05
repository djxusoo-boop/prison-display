import AppKit
import CoreVideo
let application = NSApplication.shared
var failures = 0
func check(_ value: Bool, _ name: String) { print(value ? "PASS: \(name)" : "FAIL: \(name)"); if !value { failures += 1 } }
let view = VideoView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
var pixel: CVPixelBuffer?; CVPixelBufferCreate(nil, 1600, 900, kCVPixelFormatType_32BGRA, nil, &pixel)
try view.present(pixel!)
var messages: [PointerMessage] = []; view.onPointer = { messages.append($0) }
func event(_ type: NSEvent.EventType, _ x: Double, _ y: Double, clicks: Int = 1) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
}
view.mouseDown(with: event(.leftMouseDown, 500, 350, clicks: 2))
check(messages.last == PointerMessage(action: .leftDown, x: 0.5, y: 0.5, clicks: 2), "window mapping preserves center and double click")
view.mouseDragged(with: event(.leftMouseDragged, 750, 350))
check(messages.last?.action == .move && messages.last?.x == 0.75, "drag normalized to video rather than window")
view.mouseUp(with: event(.leftMouseUp, 1200, -100))
check(messages.last?.action == .leftUp && messages.last!.x < 1 && messages.last!.y <= 1, "release outside image clamps safely")
view.mouseMoved(with: event(.mouseMoved, 500, 350))
check(messages.last?.action == .move, "mouse movement reads no scroll-only event properties")
if let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -20, wheel2: 0, wheel3: 0) {
    wheel.location = CGPoint(x: 500, y: (NSScreen.main?.frame.maxY ?? 700) - 350)
    if let input = NSEvent(cgEvent: wheel) { view.scrollWheel(with: input); check(messages.last?.action == .scroll, "wheel reads no click-only event properties") }
}
let count = messages.count
view.mouseDown(with: event(.leftMouseDown, 500, 10))
check(messages.count == count, "letterbox clicks ignored")
view.rightMouseDown(with: event(.rightMouseDown, 500, 350)); view.releaseLocalButtons()
check(messages.suffix(2).map(\.action) == [.rightDown, .rightUp], "focus loss releases held right button")
check(view.acceptsFirstMouse(for: nil), "first click activates and controls image")
view.remoteCursor(x: 0.25, y: 0.75, visible: true)
let cursor = view.layer!.sublayers![1]
check(cursor.zPosition > view.videoLayer.zPosition, "remote cursor stays above the hardware video layer")
check(!cursor.isHidden && cursor.contents != nil, "remote cursor has a visible image independent of input permission")
check(abs(cursor.frame.minX - 250) < 1 && abs(cursor.frame.maxY - (631.25 - 0.75*562.5)) < 1, "remote cursor uses top-left image coordinates")
view.remoteCursor(x: 0.25, y: 0.75, visible: false)
check(cursor.isHidden, "cursor leaving captured display is hidden")
view.cursorInVideo = true; view.remoteCursor(x: 0.25, y: 0.75, visible: true)
check(cursor.isHidden, "original cursor mode suppresses duplicate overlay")
view.cursorInVideo = false
check(!cursor.isHidden, "fast cursor mode restores overlay")
view.desktopControlActive = true
check(!cursor.isHidden, "cross-desktop control keeps the received cursor visible")
view.remoteCursor(x: 0.7, y: 0.4, visible: true)
check(!cursor.isHidden && abs(cursor.frame.minX - 700) < 1, "incoming pointer remains visible while cross-desktop control is active")
view.desktopControlActive = false
check(!cursor.isHidden && abs(cursor.frame.minX - 700) < 1, "return to iMac restores the latest cursor overlay")
var keyboardMessages: [KeyboardMessage] = []; view.onKeyboard = { keyboardMessages.append($0) }
let keyEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
check(!view.forwardKey(keyEvent, action: .down) && keyboardMessages.isEmpty, "keyboard disabled by default")
view.keyboardEnabled = true
check(!view.forwardKey(keyEvent, action: .down), "keyboard never forwarded from an inactive viewer")
final class FocusedTestWindow: NSWindow { override var isKeyWindow: Bool { true } }
let testWindow = FocusedTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.borderless], backing: .buffered, defer: true)
testWindow.contentView = view
view.mouseDown(with: event(.leftMouseDown, 500, 350))
check(view.forwardKey(keyEvent, action: .down) && keyboardMessages.last?.keyCode == 0, "enabled focused viewer forwards key")
view.keyboardEnabled = false
check(keyboardMessages.last?.action == .releaseAll, "disabling focused keyboard releases keys")
view.keyboardEnabled = true
check(!view.forwardKey(keyEvent, action: .down), "reenabling requires a fresh click")
view.mouseDown(with: event(.leftMouseDown, 500, 350))
let quitEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil, characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12)!
check(!view.forwardKey(quitEvent, action: .down), "quit shortcut remains local")
view.clear(); let cleared = messages.count; view.mouseDown(with: event(.leftMouseDown, 500, 350))
check(messages.count == cleared, "no control before image or after disconnection")
var rendered: [Double] = []
let mailbox = LatestCursorPresenter { x, _, _, _ in rendered.append(x) }
for n in 1...100 { mailbox.submit(x: Double(n), y: 0, visible: true, permitted: true) }
let cursorDeadline = Date().addingTimeInterval(2)
while rendered.isEmpty && Date() < cursorDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
check(rendered == [100], "cursor backlog renders only the latest position")
mailbox.submit(x: 101, y: 0, visible: true, permitted: true); mailbox.clear()
mailbox.submit(x: 102, y: 0, visible: true, permitted: true)
let resetDeadline = Date().addingTimeInterval(2)
while rendered.count < 2 && Date() < resetDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
check(rendered == [100,102], "old cursor cannot overwrite a new connection")
print("RESULT: \(failures) failures; no system input generated")
exit(failures == 0 ? 0 : 1)
