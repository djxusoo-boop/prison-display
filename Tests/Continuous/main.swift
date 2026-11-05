import AppKit
// Continuous pointer: protocol, geometry and receiver state machine.
// No event is posted and the real cursor is never detached.
setbuf(stdout, nil)
var failures = 0
func check(_ value: Bool, _ name: String) { print(value ? "PASS:" : "FAIL:", name); if !value { failures += 1 } }

// Messages
let moveBy = PointerMessage(action: .moveBy, x: 0, y: 0, delta: -37.5, deltaX: 120)
check((try? PointerMessage(moveBy.serialize())) == moveBy, "relative movement round-trips")
check((try? PointerMessage(PointerMessage(action: .middleDown, x: 0.2, y: 0.3).serialize()))?.action == .middleDown, "middle button round-trips")
let back = DesktopControlMessage.returned(token: 9, x: 0.25, y: 1)
let decoded = try? DesktopControlMessage(back.serialize())
check(decoded?.action == .returned && abs((decoded?.returnedPoint.x ?? 0) - 0.25) < 0.0001 && decoded?.returnedPoint.y == 1, "hand-back position round-trips")
check((try? DesktopControlMessage(DesktopControlMessage(action: .beginGlobal, token: 3).serialize()))?.action == .beginGlobal, "continuous lease request round-trips")
var invalid = DesktopControlMessage(action: .end, token: 3).serialize(); invalid[12] = 1
check((try? DesktopControlMessage(invalid)) == nil, "size fields rejected outside accepted/returned")
var tooFar = DesktopControlMessage(action: .returned, token: 3).serialize(); tooFar[9] = 1
check((try? DesktopControlMessage(tooFar)) == nil, "hand-back position outside 0...65535 rejected")

// Geometry
let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
let right = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
let above = CGRect(x: 200, y: -1440, width: 2560, height: 1440)
check(ScreenEdges.mask(of: main, among: [main, right]) == 1, "neighbour to the right")
check(ScreenEdges.mask(of: right, among: [main, right]) == 2, "neighbour to the left")
check(ScreenEdges.mask(of: main, among: [main, above]) == 4, "neighbour above")
check(ScreenEdges.mask(of: above, among: [main, above]) == 8, "neighbour below")
check(ScreenEdges.mask(of: main, among: [main, CGRect(x: 1440, y: 900, width: 100, height: 100)]) == 0, "corner contact is not an edge")
check(ScreenEdges.mask(of: main, among: [main]) == 0, "single display has no continuing edge")
check(clampToDisplays(CGPoint(x: 1500, y: 950), [main, right]) == CGPoint(x: 1500, y: 879), "point in a gap snaps to the nearest display")
check(clampToDisplays(CGPoint(x: 5000, y: 100), [main, right]) == CGPoint(x: 3359, y: 100), "point beyond the last display stays on its edge")

// Sender injector in continuous mode
let injector = PointerInjector()
var posted: [CGEvent] = []
injector.trusted = { true }; injector.post = { posted.append($0) }
injector.displays = { [main, right] }
injector.location = { CGPoint(x: 1430, y: 400) }
injector.globalMode = true
injector.receive(PointerMessage(action: .moveBy, x: 0, y: 0, delta: 10, deltaX: 40))
check(posted.last?.type == .mouseMoved && posted.last?.location == CGPoint(x: 1470, y: 410), "relative move crosses onto the next display")
check(!injector.lastMoveBlocked, "move onto a neighbouring display is not blocked")
injector.receive(PointerMessage(action: .leftDown, x: 0.9, y: 0.9))
check(posted.last?.type == .leftMouseDown && posted.last?.location == CGPoint(x: 1470, y: 410), "click uses the real cursor position, not the viewer coordinates")
injector.receive(PointerMessage(action: .moveBy, x: 0, y: 0, deltaX: 5))
check(posted.last?.type == .leftMouseDragged, "movement with the button held is a drag (selection works)")
injector.receive(PointerMessage(action: .leftUp, x: 0, y: 0))
injector.receive(PointerMessage(action: .moveBy, x: 0, y: 0, deltaX: 120)); for _ in 0..<20 { injector.receive(PointerMessage(action: .moveBy, x: 0, y: 0, deltaX: 120)) }
check(injector.lastMoveBlocked && injector.position.x == 3359, "pushing past the last display is reported as blocked")
injector.receive(PointerMessage(action: .middleDown, x: 0, y: 0))
check(posted.last?.type == .otherMouseDown && posted.last?.getIntegerValueField(.mouseEventButtonNumber) == 2, "middle button reaches the sending Mac")
injector.releaseButtons()
check(posted.last?.type == .otherMouseUp, "releasing buttons includes the middle button")
injector.globalMode = false; injector.displayID = 0
let before = posted.count
injector.receive(PointerMessage(action: .moveBy, x: 0, y: 0, deltaX: 5))
check(posted.count == before, "relative movement ignored outside continuous mode")

// Receiver controller
var clock: UInt64 = 1_000_000_000
var controls: [DesktopControlMessage] = [], pointers: [PointerMessage] = [], keys: [KeyboardMessage] = []
var warped: [CGPoint?] = [], changes: [Bool] = []
var associated = true, hidden = false
let c = ContinuousPointer()
c.now = { clock }
c.sendControl = { controls.append($0) }; c.sendPointer = { pointers.append($0) }; c.sendKeyboard = { keys.append($0) }
c.warp = { warped.append($0) }; c.onChanged = { changes.append($0) }
c.cursor.isForeground = { true }
c.cursor.associate = { associated = $0; return .success }
c.cursor.visibility = { hidden = $0 }
check(!c.push(edgeIndex: 0), "no crossing before the sender reports a continuing edge")
c.edges = 1
check(!c.push(edgeIndex: 1), "no crossing toward an edge without a display")
check(c.push(edgeIndex: 0) && controls.last?.action == .beginGlobal && c.state == .requesting, "push toward a display requests the lease")
let token = c.token
c.reply(DesktopControlMessage(action: .accepted, token: token &+ 1, width: 100, height: 100))
check(c.state == .requesting, "reply for another token ignored")
c.reply(DesktopControlMessage(action: .accepted, token: token, width: 1920, height: 1080))
check(c.isActive && !associated && hidden && changes == [true], "accepted: local cursor detached and hidden")
c.move(dx: 300, dy: -10)
check(pointers.count == 3 && pointers.map { $0.deltaX } == [120, 120, 60] && pointers.allSatisfy { $0.action == .moveBy }, "large movement split into valid steps")
c.button(.leftDown, clicks: 2)
c.scroll(dy: 500, dx: 0)
check(pointers.last?.action == .scroll && pointers.last?.delta == 120, "scroll clamped to the protocol range")
clock += 600_000_000; c.tick()
check(controls.last?.action == .heartbeat, "heartbeat keeps the lease")
c.leave()
check(pointers.last?.action == .leftUp && keys.last?.action == .releaseAll && controls.last?.action == .end, "leaving releases the held click and keys")
check(associated && !hidden && changes == [true, false] && warped.count == 1 && warped[0] == nil, "leaving restores the local cursor")
check(!c.push(edgeIndex: 0), "short cooldown avoids bouncing at the edge")
clock += 500_000_000
check(c.push(edgeIndex: 0), "crossing available again after the cooldown")
c.reply(DesktopControlMessage(action: .accepted, token: c.token, width: 1920, height: 1080))
c.button(.rightDown)
let sent = pointers.count
c.reply(DesktopControlMessage.returned(token: c.token, x: 0.98, y: 0.4))
check(pointers.count == sent && c.state == .idle && associated, "hand-back from the sender does not send stray releases")
check(warped.last.map { $0.map { abs($0.x - 0.98) < 0.001 && abs($0.y - 0.4) < 0.001 } ?? false } ?? false, "local cursor placed where the remote one came back")
clock += 500_000_000
c.push(edgeIndex: 0); clock += 1_100_000_000; c.tick()
check(c.state == .idle, "unanswered request times out")
clock += 500_000_000
c.push(edgeIndex: 0); c.reply(DesktopControlMessage(action: .accepted, token: c.token, width: 10, height: 10))
clock += 3_000_000_000; c.tick()
check(c.state == .idle && associated, "silent sender returns control to this screen")
c.enabled = false; clock += 500_000_000
check(!c.push(edgeIndex: 0), "disabled continuous mode never crosses")
print("RESULT: \(failures) failures; synthetic events only, nothing posted")
exit(failures == 0 ? 0 : 1)
