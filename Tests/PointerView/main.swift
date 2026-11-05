import AppKit
import CoreVideo
let application = NSApplication.shared
var failures = 0
func check(_ value: Bool, _ name: String) { print(value ? "PASS: \(name)" : "FAIL: \(name)"); if !value { failures += 1 } }
let view = VideoView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
let fixtureWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.borderless], backing: .buffered, defer: true)
fixtureWindow.contentView = view
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
    // CGEvent uses Quartz top-left coordinates; NSEvent uses AppKit bottom-left
    // coordinates. CGMainDisplayID is always anchored at Quartz (0,0), even
    // when other monitors give NSScreen.main a shifted AppKit origin.
    let mainDisplay = CGMainDisplayID()
    wheel.location = CGPoint(x: 500, y: mainDisplay == 0 ? -350 : CGDisplayBounds(mainDisplay).maxY - 350)
    if let input = NSEvent(cgEvent: wheel) {
        view.scrollWheel(with: input)
        if messages.last?.action != .scroll { print("WHEEL TEST LOCATION", input.locationInWindow, view.convert(input.locationInWindow, from: nil), view.bounds) }
        check(messages.last?.action == .scroll, "wheel reads no click-only event properties")
    }
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
// Regression: fullscreen crop and pointer coordinates must share one transform.
view.videoLayer.videoGravity = .resizeAspectFill
view.mouseMoved(with: event(.mouseMoved, 250, 350))
check(abs((messages.last?.x ?? -1) - 0.299107142857) < 0.0001, "fullscreen click maps to the cropped image, not the letterbox transform")
view.remoteCursor(x: 0.25, y: 0.75, visible: true)
check(abs(cursor.frame.minX - 188.8888889) < 1, "fullscreen cursor overlay follows the same crop as video")
let beforeFilledEdge = messages.count
view.mouseDown(with: event(.leftMouseDown, 500, 10))
check(messages.count == beforeFilledEdge + 1, "fullscreen image is interactive where letterbox used to be")
view.mouseUp(with: event(.leftMouseUp, 1300, 350))
check(abs((messages.last?.x ?? -1) - 0.901785) < 0.0001, "fullscreen outside release clamps to visible content")
view.videoLayer.videoGravity = .resizeAspect
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
let copyEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!
check(view.performKeyEquivalent(with: copyEvent) && keyboardMessages.last?.keyCode == 8, "copy shortcut reaches the remote desktop before local menus")
let localQuitEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil, characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12)!
let beforeLocalShortcut = keyboardMessages.count
_ = view.performKeyEquivalent(with: localQuitEvent)
check(keyboardMessages.count == beforeLocalShortcut, "quit shortcut remains local")
testWindow.makeFirstResponder(nil)
let unfocusedCount = keyboardMessages.count
check(!view.performKeyEquivalent(with: copyEvent) && keyboardMessages.count == unfocusedCount, "keyboard shortcuts stay local after viewer loses focus")
view.mouseDown(with: event(.leftMouseDown, 500, 350))


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
// A remote cursor must not synchronously query the local mouse per update.
final class CursorQueryWindow: NSWindow {
    var queries = 0
    override var isKeyWindow: Bool { true }
    override var mouseLocationOutsideOfEventStream: NSPoint { queries += 1; return NSPoint(x: 500, y: 350) }
}
let cursorWindow = CursorQueryWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.borderless], backing: .buffered, defer: true)
let remoteView = VideoView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
cursorWindow.contentView = remoteView
try remoteView.present(pixel!)
cursorWindow.queries = 0
let cursorStart = monotonicNS()
for i in 0..<1000 { remoteView.remoteCursor(x: Double(i % 100)/100, y: 0.5, visible: true) }
print("REMOTE CURSOR queries=\(cursorWindow.queries) updates=1000 elapsedMS=\(Double(monotonicNS()-cursorStart)/1e6)")
check(cursorWindow.queries == 0, "remote cursor does not query the local mouse")
remoteView.mouseDown(with: event(.leftMouseDown, 500, 350))
check(cursorWindow.queries > 0, "local mouse still suppresses its delayed remote duplicate")
remoteView.mouseUp(with: event(.leftMouseUp, 500, 350))
var changedPixel: CVPixelBuffer?
CVPixelBufferCreate(nil, 800, 800, kCVPixelFormatType_32BGRA, nil, &changedPixel)
try remoteView.present(changedPixel!)
var resizedInput: PointerMessage?
remoteView.onPointer = { resizedInput = $0 }
remoteView.mouseMoved(with: event(.mouseMoved, 325, 350))
check(abs((resizedInput?.x ?? -1) - 0.25) < 0.001, "format reuse preserves changed resolution and input mapping")
remoteView.clear()
try remoteView.present(pixel!)
check(remoteView.acceptedFrames > 0, "video resumes after clearing the cached format")

let sharingWindow = FocusedTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.borderless], backing: .buffered, defer: true)
let sharingView = VideoView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
sharingWindow.contentView = sharingView
check(try sharingView.present(pixel!), "sharing fixture has its first video image")
var sharingInput: PointerMessage?
sharingView.onPointer = { sharingInput = $0 }
sharingView.keyboardEnabled = true
sharingWindow.makeFirstResponder(sharingView)
var independentKeys: [KeyboardMessage] = []
sharingView.onKeyboard = { independentKeys.append($0) }
sharingView.mouseDown(with: event(.leftMouseDown, 500, 350))
sharingView.mouseEnabled = false
check(sharingInput?.action == .leftUp, "disabling shared mouse releases held button")
let inputBeforeDisabled = sharingInput
sharingView.mouseMoved(with: event(.mouseMoved, 600, 350))
check(sharingInput == inputBeforeDisabled, "disabled mouse sends no movement")
check(sharingView.forwardKey(keyEvent, action: .down), "keyboard still works while mouse sharing is off")
sharingView.keyboardEnabled = false
check(independentKeys.last?.action == .releaseAll, "disabling shared keyboard releases held key")
sharingView.mouseEnabled = true
sharingView.mouseMoved(with: event(.mouseMoved, 600, 350))
check(sharingInput?.action == .move && !sharingView.forwardKey(keyEvent, action: .down), "mouse still works while keyboard sharing is off")
print("RESULT: \(failures) failures; no system input generated")
exit(failures == 0 ? 0 : 1)
