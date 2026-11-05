import AppKit
var failures = 0
func check(_ value: Bool, _ name: String) { print(value ? "PASS: \(name)" : "FAIL: \(name)"); if !value { failures += 1 } }
for action in [PointerMessage.Action.move, .leftDown, .leftUp, .rightDown, .rightUp, .scroll] {
    let value = PointerMessage(action: action, x: 0.25, y: 0.75, delta: -45, clicks: 2)
    check((try? PointerMessage(value.serialize())) == value, "pointer packet roundtrip \(action)")
}
for data in [Data(), Data(repeating: 0, count: 25), PointerMessage(action: .move, x: .nan, y: 0).serialize(), PointerMessage(action: .move, x: 1.1, y: 0).serialize(), PointerMessage(action: .scroll, x: 0, y: 0, delta: 121).serialize()] {
    check((try? PointerMessage(data)) == nil, "invalid pointer rejected")
}
let wheelMessage = PointerMessage(action: .scroll, x: 0.5, y: 0.5, delta: -10, deltaX: 20, flags: CGEventFlags.maskCommand.rawValue)
check((try? PointerMessage(wheelMessage.serialize())) == wheelMessage, "horizontal wheel and modifier preserved")
check((try? PointerMessage(PointerMessage(action: .scroll, x: 0.5, y: 0.5, deltaX: .nan).serialize())) == nil, "invalid horizontal wheel rejected")
for action in [KeyboardMessage.Action.down, .up, .modifiers, .releaseAll] {
    let value = KeyboardMessage(action: action)
    check((try? KeyboardMessage(value.serialize())) == value, "keyboard packet roundtrip")
}
check((try? KeyboardMessage(KeyboardMessage(action: .down, keyCode: 128).serialize())) == nil, "out of range key rejected")
check((try? KeyboardMessage(KeyboardMessage(action: .releaseAll, keyCode: 1).serialize())) == nil, "malformed release rejected")
var badKey = KeyboardMessage(action: .down).serialize(); badKey[11] = 2
check((try? KeyboardMessage(badKey)) == nil, "invalid repeat flag rejected")
let rect = CGRect(x: -1920, y: -500, width: 1920, height: 1080)
let point = PointerMessage(action: .move, x: 1, y: 1).point(in: rect)
check(point == CGPoint(x: -1, y: 579), "global mapping handles negative display origin and stays inside bounds")
check(PointerMessage.normalized(CGPoint(x: 10, y: 10), in: rect) == nil, "letterbox or outside display rejected")
check(PointerMessage.normalized(CGPoint(x: -960, y: 40), in: rect) == CGPoint(x: 0.5, y: 0.5), "normalized center maps correctly")
#if SENDER
let injector = PointerInjector(); injector.displayID = CGMainDisplayID()
var events: [CGEvent] = []; injector.post = { events.append($0) }
injector.trusted = { false }
injector.receive(PointerMessage(action: .leftDown, x: 0.5, y: 0.5))
check(events.isEmpty, "input blocked without accessibility permission")
injector.trusted = { true }
for action in [PointerMessage.Action.leftDown, .move, .leftUp, .rightDown, .move, .rightUp, .scroll] { injector.receive(PointerMessage(action: action, x: 0.5, y: 0.5, delta: -40, clicks: 2)) }
check(events.map(\.type) == [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseDragged, .rightMouseUp, .scrollWheel], "click drag right click and scrolling generate correct events without posting")
check(events.first?.getIntegerValueField(.mouseEventClickState) == 2, "double click count preserved")
events = []; injector.receive(PointerMessage(action: .leftDown, x: 0.5, y: 0.5)); injector.releaseButtons()
check(events.map(\.type) == [.leftMouseDown, .leftMouseUp], "disconnect releases held buttons")
events = []; injector.releaseButtons(); check(events.isEmpty, "release is idempotent")
#endif
#if SENDER
let keyboard = KeyboardInjector(); var keys: [CGEvent] = []; keyboard.post = { keys.append($0) }
keyboard.trusted = { false }; keyboard.receive(KeyboardMessage(action: .down, keyCode: 0)); check(keys.isEmpty, "keyboard blocked without accessibility")
keyboard.trusted = { true }
keyboard.receive(KeyboardMessage(action: .modifiers, keyCode: 56, flags: CGEventFlags.maskShift.rawValue))
keyboard.receive(KeyboardMessage(action: .down, keyCode: 0, flags: CGEventFlags.maskShift.rawValue))
keyboard.receive(KeyboardMessage(action: .down, keyCode: 0, repeated: true))
check(keys.map(\.type) == [.flagsChanged, .keyDown, .keyDown] && keys.last?.getIntegerValueField(.keyboardEventAutorepeat) == 1, "keyboard modifiers and repeats generated without posting")
keyboard.releaseKeys(); check(keys.suffix(2).map(\.type) == [.keyUp, .flagsChanged], "disconnect releases ordinary and modifier keys")
let keyCount = keys.count; keyboard.releaseKeys(); check(keys.count == keyCount, "keyboard release idempotent")
#endif
var queries = 0
var rectangle = CGRect(x: 1710, y: -100, width: 1920, height: 1080)
let geometry = DisplayGeometry(watchesDisplays: false, query: { _ in queries += 1; return rectangle })
for _ in 0..<1000 { _ = geometry.bounds(42) }
check(queries == 1, "mouse geometry is queried once for 1000 unchanged positions")
rectangle = CGRect(x: -2560, y: 200, width: 2560, height: 1440)
geometry.invalidate()
check(geometry.bounds(42) == rectangle && queries == 2, "display rearrangement invalidates cursor geometry")
_ = geometry.bounds(43)
check(queries == 3, "a different display has its own geometry")
rectangle = .zero; geometry.invalidate(); _ = geometry.bounds(42)
rectangle = CGRect(x: 0, y: 0, width: 1280, height: 720)
check(geometry.bounds(42) == rectangle, "temporary missing display is not cached")
print("RESULT: \(failures) failures; no events posted to desktop")
exit(failures == 0 ? 0 : 1)
