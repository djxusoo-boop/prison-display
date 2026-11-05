import AppKit
import CoreGraphics
var failures = 0
func check(_ value: Bool, _ text: String) { print("\(value ? "PASS" : "FAIL"): \(text)"); if !value { failures += 1 } }
let rect = CGRect(x: -1440, y: -300, width: 1440, height: 900)
let remote = CGSize(width: 1920, height: 1080)
let cases: [(DesktopEdge, CGPoint, CGPoint)] = [(.right, CGPoint(x: -1,y: 150), CGPoint(x: 4,y: 0)), (.left, CGPoint(x: -1440,y: 150), CGPoint(x: -4,y: 0)), (.above, CGPoint(x: -720,y: -300), CGPoint(x: 0,y: -4)), (.below, CGPoint(x: -720,y: 599), CGPoint(x: 0,y: 4))]
for (edge, point, delta) in cases {
    check(edge.crossing(point: point, delta: delta, bounds: rect), "outward edge crossing \(edge)")
    check(!edge.crossing(point: point, delta: CGPoint(x: -delta.x,y: -delta.y), bounds: rect), "inward movement stays local \(edge)")
    let entry = edge.entry(point: point, bounds: rect, remote: remote)
    check(CGRect(origin: .zero, size: remote).contains(entry) && !edge.returning(entry, remote: remote), "entry remains inside different-size remote screen \(edge)")
}
for action in [DesktopControlMessage.Action.begin, .end, .heartbeat, .rejected] {
    let message = DesktopControlMessage(action: action, token: 7)
    check((try? DesktopControlMessage(message.serialize()))?.token == 7, "control packet roundtrip \(action)")
}
for data in [Data(), Data(repeating: 0, count: 17), DesktopControlMessage(action: .accepted, token: 7).serialize(), DesktopControlMessage(action: .begin, token: 7, width: 1).serialize(), DesktopControlMessage(action: .accepted, token: 7, width: 32769, height: 10).serialize()] {
    check((try? DesktopControlMessage(data)) == nil, "malformed control packet rejected")
}
let bridge = DesktopBridge(); bridge.cursor.isForeground = { true }; bridge.cursor.associate = { _ in .success }; bridge.focus = { _ in }; bridge.protectedInput = { false }; bridge.buttonHeld = { false }; var time: UInt64 = 10_000_000_000
bridge.now = { time }; bridge.bounds = { CGRect(x: 0,y: 0,width: 1000,height: 800) }
var controls: [DesktopControlMessage] = [], pointers: [PointerMessage] = [], keys: [KeyboardMessage] = [], visibility: [Bool] = [], warps: [CGPoint] = []
bridge.sendControl = { controls.append($0) }; bridge.sendPointer = { pointers.append($0) }; bridge.sendKeyboard = { keys.append($0) }; bridge.hide = { visibility.append($0) }; bridge.warp = { warps.append($0) }
func move(_ x: Double, _ y: Double, _ dx: Double, _ dy: Double) -> CGEvent {
    let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x:x,y:y), mouseButton: .left)!
    event.setDoubleValueField(.mouseEventDeltaX, value: dx); event.setDoubleValueField(.mouseEventDeltaY, value: dy); event.flags = []; return event
}
let crossing = move(999,400,5,0)
check(!bridge.handle(.mouseMoved, crossing) && controls.isEmpty, "disconnected iMac input stays local")
bridge.connected = true
check(!bridge.handle(.mouseMoved, crossing) && controls.last?.action == .begin, "crossing requests authenticated control without swallowing input")
let token = bridge.token
bridge.reply(DesktopControlMessage(action: .accepted, token: token+1, width: 1920, height: 1080))
check(!bridge.remote && visibility.isEmpty, "stale approval cannot capture input")
bridge.reply(DesktopControlMessage(action: .accepted, token: token, width: 1920, height: 1080))
check(bridge.remote && visibility == [true] && pointers.last?.x == 2.0/1919, "approved crossing enters correct remote edge")
check(bridge.handle(.mouseMoved, move(999,400,50,20)) && pointers.last!.x > 0.02, "relative physical movement forwarded without posting to desktop")
let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
check(bridge.handle(.keyDown, down) && keys.last?.action == .down, "keyboard follows remote pointer")
let click = CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:.zero,mouseButton:.left)!
check(bridge.handle(.leftMouseDown, click), "remote click suppresses local click")
bridge.connected = false
check(!bridge.remote && keys.last?.action == .releaseAll && pointers.last?.action == .leftUp && visibility == [true,false] && warps.count == 1, "disconnect returns cursor and releases held input")
bridge.leave(); check(visibility.count == 2 && warps.count == 1, "return is idempotent")
time += 1_000_000_000; bridge.connected = true
_ = bridge.handle(.mouseMoved, crossing); let next = bridge.token
bridge.reply(DesktopControlMessage(action:.accepted,token:next,width:1920,height:1080))
check(bridge.remote, "new connection can transfer control")
time += 2_100_000_000; bridge.tick()
check(!bridge.remote && controls.last?.action == .end, "missing heartbeat returns control within two seconds")
time += 1_000_000_000; _ = bridge.handle(.mouseMoved,crossing)
bridge.leave(); bridge.reply(DesktopControlMessage(action:.accepted,token:bridge.token,width:1920,height:1080))
check(!bridge.remote, "late approval after cancellation ignored")
time += 1_000_000_000; _ = bridge.handle(.mouseMoved,crossing)
bridge.reply(DesktopControlMessage(action:.accepted,token:bridge.token,width:1920,height:1080))
check(bridge.handle(.mouseMoved,move(999,400,-5,0)) && !bridge.remote, "opposite remote edge returns to iMac")
time += 1_000_000_000; _ = bridge.handle(.mouseMoved,crossing)
bridge.reply(DesktopControlMessage(action:.accepted,token:bridge.token,width:1920,height:1080))
let escape = CGEvent(keyboardEventSource:nil,virtualKey:53,keyDown:true)!; escape.flags = [.maskControl,.maskAlternate]
check(bridge.handle(.keyDown,escape) && !bridge.remote, "emergency shortcut returns control")
time += 1_000_000_000; _ = bridge.handle(.mouseMoved,crossing)
let cancelled = bridge.token
_ = bridge.handle(.mouseMoved,move(500,400,-10,0))
bridge.reply(DesktopControlMessage(action:.accepted,token:cancelled,width:1920,height:1080))
check(!bridge.remote, "moving away from edge cancels pending transfer")
time += 1_000_000_000
_ = bridge.handle(.keyDown,down); let beforeHeldKey = controls.count
_ = bridge.handle(.mouseMoved,crossing)
check(controls.count == beforeHeldKey, "held local key prevents crossing")
let up = CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:false)!
_ = bridge.handle(.keyUp,up)
time += 1_000_000_000; bridge.buttonHeld = { true }; let beforeHeldMouse = controls.count
_ = bridge.handle(.mouseMoved,crossing)
check(controls.count == beforeHeldMouse, "held local button prevents transfer")
bridge.buttonHeld = { false }; _ = bridge.handle(.mouseMoved,crossing)
bridge.reply(DesktopControlMessage(action:.accepted,token:bridge.token,width:1920,height:1080))
bridge.protectedInput = { true }; let beforeProtected = pointers.count
check(!bridge.handle(.mouseMoved,move(999,400,15,0)) && !bridge.remote && pointers.count == beforeProtected, "protected input returns control without forwarding the event")
check(pointers.allSatisfy { (try? PointerMessage($0.serialize())) != nil }, "all forwarded coordinates remain valid")

// No actual OS cursor operations: the asynchronous activation is simulated.
bridge.protectedInput = { false }; time += 1_000_000_000
var foreground = false, associations: [Bool] = [], activeStates: [Bool] = []
bridge.cursor.isForeground = { foreground }
bridge.cursor.associate = { associations.append($0); return .success }
bridge.onControlChanged = { activeStates.append($0) }
let hidesBefore = visibility.count, inputsBefore = pointers.count
_ = bridge.handle(.mouseMoved, crossing)
bridge.reply(DesktopControlMessage(action: .accepted, token: bridge.token, width: 1920, height: 1080))
check(!bridge.remote && visibility.count == hidesBefore && associations.isEmpty && pointers.count == inputsBefore, "ACK waits for foreground without hiding or forwarding input")
foreground = true; bridge.applicationDidBecomeActive()
check(bridge.remote && associations == [false] && visibility.count == hidesBefore+1 && activeStates == [true], "activation hides and detaches the local cursor before remote input")
bridge.applicationDidBecomeActive()
check(associations == [false] && visibility.count == hidesBefore+1, "duplicate activation does not add a hide count")
foreground = false; bridge.applicationDidResignActive()
check(!bridge.remote && associations == [false,true] && visibility.count == hidesBefore+2 && activeStates == [true,false], "changing apps restores local cursor and overlay ownership")
time += 1_000_000_000; _ = bridge.handle(.mouseMoved, crossing)
bridge.reply(DesktopControlMessage(action: .accepted, token: bridge.token, width: 1920, height: 1080))
bridge.leave(); foreground = true; bridge.applicationDidBecomeActive()
check(!bridge.remote && associations.count == 2, "late foreground notification after cancellation never hides the cursor")
time += 1_000_000_000; foreground = false; _ = bridge.handle(.mouseMoved, crossing)
bridge.reply(DesktopControlMessage(action: .accepted, token: bridge.token, width: 1920, height: 1080))
time += 1_100_000_000; bridge.tick(); foreground = true; bridge.applicationDidBecomeActive()
check(!bridge.remote && associations.count == 2, "foreground activation deadline returns local control")
time += 1_000_000_000; bridge.cursor.associate = { associations.append($0); return .failure }
_ = bridge.handle(.mouseMoved, crossing)
bridge.reply(DesktopControlMessage(action: .accepted, token: bridge.token, width: 1920, height: 1080))
check(!bridge.remote && !bridge.cursor.hidden && !bridge.cursor.detached && visibility.count == hidesBefore+2, "failed cursor detachment preserves visible local control")
var restoreAllowed = false
bridge.cursor.associate = { associations.append($0); return $0 && !restoreAllowed ? .failure : .success }
time += 1_000_000_000; _ = bridge.handle(.mouseMoved, crossing)
bridge.reply(DesktopControlMessage(action: .accepted, token: bridge.token, width: 1920, height: 1080))
bridge.leave()
check(!bridge.remote && !bridge.cursor.hidden && bridge.cursor.detached, "restore failure balances hide while retaining retry ownership")
restoreAllowed = true; bridge.tick()
check(!bridge.cursor.detached, "idle watchdog retries failed physical cursor restoration")
time += 1_000_000_000; _ = bridge.handle(.mouseMoved, crossing)
bridge.reply(DesktopControlMessage(action: .accepted, token: bridge.token, width: 1920, height: 1080))
bridge.stop()
check(!bridge.remote && !bridge.cursor.hidden && !bridge.cursor.detached && visibility.filter { $0 }.count == visibility.filter { !$0 }.count, "stop balances all hide counts and restores the physical mouse")
var finalVisibility: [Bool] = [], finalAssociation: [Bool] = []
do {
    let lease = LocalCursorLease(); lease.isForeground = { true }
    lease.visibility = { finalVisibility.append($0) }; lease.associate = { finalAssociation.append($0); return .success }
    check(lease.acquire() && lease.acquire(), "cursor ownership acquisition is idempotent")
}
check(finalVisibility == [true,false] && finalAssociation == [false,true], "cursor owner destruction restores visibility and physical movement")

print("RESULT: \(failures) failures; no event tap installed or desktop input posted")
exit(failures == 0 ? 0 : 1)
