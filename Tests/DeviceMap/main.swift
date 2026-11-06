import AppKit
// Screen map with simulated displays: snapping, dragging and a rendered preview.
setbuf(stdout, nil)
var failures = 0
func check(_ value: Bool, _ name: String) { print(value ? "PASS:" : "FAIL:", name); if !value { failures += 1 } }
_ = NSApplication.shared
let air = CGRect(x: 0, y: 0, width: 1470, height: 956)
let pro = CGRect(x: 1470, y: -200, width: 2560, height: 1440)
let imac = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
// Snapping
check(DeviceMapView.snap(CGRect(x: 1500, y: 100, width: 800, height: 600), against: [air]) == CGPoint(x: 1470, y: 100), "a screen dropped near the right edge sticks to it")
check(DeviceMapView.snap(CGRect(x: 200, y: -650, width: 800, height: 600), against: [air]) == CGPoint(x: 200, y: -600), "a screen dropped above sticks to the top edge")
let s = DeviceMapView.snap(CGRect(x: 1400, y: 0, width: 800, height: 600), against: [air, pro])
check(!CGRect(origin: s, size: CGSize(width: 800, height: 600)).insetBy(dx: 1, dy: 1).intersects(air) && !CGRect(origin: s, size: CGSize(width: 800, height: 600)).insetBy(dx: 1, dy: 1).intersects(pro), "a snapped screen never overlaps another")
// View with fake displays
let view = DeviceMapView(frame: NSRect(x: 0, y: 0, width: 620, height: 230))
view.screens = { [
    .init(id: 1, bounds: air, title: "Este Mac", detail: "1470 × 956", main: true, virtual: false),
    .init(id: 2, bounds: pro, title: "MacBook Pro", detail: "2560 × 1440", main: false, virtual: true),
    .init(id: 3, bounds: imac, title: "iMac", detail: "1920 × 1080", main: false, virtual: true)] }
var moved: [(CGDirectDisplayID, CGPoint)] = []; var edges: [DesktopEdge] = []
view.onMoveScreen = { moved.append(($0, $1)) }
view.onPCEdge = { edges.append($0) }
view.pcName = "TORRE"; view.pcEdge = .right
let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = view; view.reload()
func event(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: view.convert(p, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
}
// The PC block sits right; drag it to the left side.
view.mouseDown(with: event(.leftMouseDown, CGPoint(x: 560, y: 115)))
view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 10, y: 115)))
view.mouseUp(with: event(.leftMouseUp, CGPoint(x: 10, y: 115)))
check(edges == [.left] && view.pcEdge == .left, "dragging the PC chooses the crossing edge")
view.pcEdge = .right; edges.removeAll()
// The iMac sits left of the Air: drag from its centre far below the Air.
let imacPoint = CGPoint(x: 194, y: 116)
view.mouseDown(with: event(.leftMouseDown, imacPoint))
view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 290, y: 200)))
view.mouseUp(with: event(.leftMouseUp, CGPoint(x: 290, y: 200)))
check(moved.count == 1 && moved[0].0 == 3, "dragging a screen moves that screen")
if let m = moved.first {
    let r = CGRect(origin: m.1, size: imac.size)
    check(!r.insetBy(dx: 1, dy: 1).intersects(air) && !r.insetBy(dx: 1, dy: 1).intersects(pro) && (abs(r.minY - air.maxY) < 1 || abs(r.maxY - air.minY) < 1 || abs(r.maxX - air.minX) < 1 || abs(r.minX - air.maxX) < 1 || abs(r.minY - pro.maxY) < 1 || abs(r.maxX - pro.minX) < 1), "it lands touching a neighbour (\(r))")
}
// The main screen never moves.
let before = moved.count
view.mouseDown(with: event(.leftMouseDown, CGPoint(x: 250, y: 120)))
view.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 300, y: 150)))
view.mouseUp(with: event(.leftMouseUp, CGPoint(x: 300, y: 150)))
check(moved.count == before, "the main screen stays fixed")
// Preview image
view.display()
if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/map.png"))
}
print("RESULT: \(failures) failures; simulated displays, nothing rearranged")
exit(failures == 0 ? 0 : 1)
