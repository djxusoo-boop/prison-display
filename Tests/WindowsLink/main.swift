import AppKit
import Network
// End to end: the Mac link against the real Windows agent and encrypted
// listener, compiled for macOS with a recording sink. Synthetic events only.
setbuf(stdout, nil)
var failures = 0
func check(_ value: Bool, _ name: String) { print(value ? "PASS:" : "FAIL:", name); if !value { failures += 1 } }
func pump(_ condition: () -> Bool, timeout: Double = 6) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    return condition()
}
let host = CommandLine.arguments[1]
let key = "0123456789ABCDEF0123456789ABCDEF"
let port = UInt16(41000 + Int(getpid() % 2000))
var output: [String] = []
let lock = NSLock()
func lines() -> [String] { lock.lock(); defer { lock.unlock() }; return output }
let agent = Process(); agent.executableURL = URL(fileURLWithPath: host); agent.arguments = [key, String(port)]
let pipe = Pipe(); agent.standardOutput = pipe
var partial = ""
pipe.fileHandleForReading.readabilityHandler = { handle in
    let text = String(data: handle.availableData, encoding: .utf8) ?? ""
    lock.lock(); partial += text
    while let newline = partial.firstIndex(of: "\n") { output.append(String(partial[..<newline])); partial = String(partial[partial.index(after: newline)...]) }
    lock.unlock()
}
try agent.run()
defer { agent.terminate() }
check(pump({ lines().contains { $0.hasPrefix("STATUS Esperando") } }), "simulated PC listens with its key")

let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
func configure(_ link: WindowsLink) {
    link.displays = { [screen] }
    let b = link.bridge
    b.cursor.isForeground = { true }; b.cursor.associate = { _ in .success }; b.cursor.visibility = { _ in }
    b.protectedInput = { false }; b.buttonHeld = { false }; b.focus = { _ in }; b.warp = { _ in }
    b.edge = .right
}
let link = WindowsLink(); configure(link)
// start() owns this timer with a real event tap; tests drive the same tick.
let ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in link.bridge.tick() }
var statuses: [String] = []; var connectedName: String?
link.onStatus = { statuses.append($0) }; link.onConnected = { connectedName = $0 }
try link.connect(host: "127.0.0.1", port: port, key: key, startBridge: false)
check(pump({ link.bridge.connected }) && connectedName == "Torre simulada", "Mac link authenticates with TLS-PSK and the PC hello")
check(pump({ lines().contains { $0.contains("Conectado con") } }), "PC shows the connected Mac")

func mouse(_ type: CGEventType, at point: CGPoint, dx: Double = 0, dy: Double = 0) -> CGEvent {
    let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
    e.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx)); e.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy)); return e
}
func key(_ code: CGKeyCode, down: Bool, flags: CGEventFlags = []) -> CGEvent {
    let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!; e.flags = flags; return e
}
_ = link.bridge.handle(.mouseMoved, mouse(.mouseMoved, at: CGPoint(x: 700, y: 450), dx: 5))
check(!link.bridge.remote, "moving inside the Mac screens does not cross")
_ = link.bridge.handle(.mouseMoved, mouse(.mouseMoved, at: CGPoint(x: 1439, y: 450), dx: 6))
check(pump({ link.bridge.remote }), "pushing the right edge hands mouse and keyboard to the PC")
check(pump({ lines().contains { $0.hasPrefix("EVENT move 0.0") } }), "the PC cursor enters from its left edge")
for _ in 0..<10 { _ = link.bridge.handle(.mouseMoved, mouse(.mouseMoved, at: CGPoint(x: 1439, y: 450), dx: 64, dy: 10)) }
_ = link.bridge.handle(.leftMouseDown, mouse(.leftMouseDown, at: CGPoint(x: 1439, y: 450)))
_ = link.bridge.handle(.leftMouseUp, mouse(.leftMouseUp, at: CGPoint(x: 1439, y: 450)))
_ = link.bridge.handle(.flagsChanged, key(55, down: true, flags: .maskCommand))
_ = link.bridge.handle(.keyDown, key(8, down: true, flags: .maskCommand))
_ = link.bridge.handle(.keyUp, key(8, down: false, flags: .maskCommand))
_ = link.bridge.handle(.flagsChanged, key(55, down: false))
check(pump({ lines().contains("EVENT left up") }), "click reaches the PC")
_ = pump({ lines().contains("EVENT key 1D up") })
let events = lines().filter { $0.hasPrefix("EVENT") }
if let move = events.last(where: { $0.hasPrefix("EVENT move") }) {
    let parts = move.split(separator: " "); let x = Double(parts[2]) ?? 0
    check(x > 0.2 && x < 0.3, "cursor travels across the PC desktop at native speed (\(move))")
}
let keys = events.filter { $0.hasPrefix("EVENT key") }
check(keys == ["EVENT key 1D down", "EVENT key 2E down", "EVENT key 2E up", "EVENT key 1D up"], "⌘C arrives as Ctrl+C on the PC \(keys)")
_ = pump({ false }, timeout: 3.5)
check(link.bridge.remote, "heartbeats keep control on the PC")
_ = link.bridge.handle(.leftMouseDown, mouse(.leftMouseDown, at: CGPoint(x: 1439, y: 450)))
for _ in 0..<40 { if !link.bridge.remote { break }; _ = link.bridge.handle(.mouseMoved, mouse(.mouseMoved, at: CGPoint(x: 1439, y: 450), dx: -100)) }
_ = link.bridge.handle(.leftMouseUp, mouse(.leftMouseUp, at: CGPoint(x: 1439, y: 450)))
for _ in 0..<40 { if !link.bridge.remote { break }; _ = link.bridge.handle(.mouseMoved, mouse(.mouseMoved, at: CGPoint(x: 1439, y: 450), dx: -100)) }
check(!link.bridge.remote, "returning through the left edge of the PC gives control back to the Mac")
_ = link.bridge.handle(.flagsChanged, key(56, down: true, flags: .maskShift))
check(pump({ false }, timeout: 0.3) == false && !lines().contains("EVENT key 2A down"), "keys typed on the Mac after returning stay on the Mac")
_ = link.bridge.handle(.mouseMoved, mouse(.mouseMoved, at: CGPoint(x: 1439, y: 450), dx: 6))
check(!link.bridge.remote, "a held modifier never carries across")
_ = link.bridge.handle(.flagsChanged, key(56, down: false))
_ = pump({ false }, timeout: 0.6)
_ = link.bridge.handle(.mouseMoved, mouse(.mouseMoved, at: CGPoint(x: 1439, y: 450), dx: 6))
check(pump({ link.bridge.remote }), "crossing again after the cooldown")
_ = link.bridge.handle(.keyDown, key(0, down: true))
check(pump({ lines().contains("EVENT key 1E down") }), "key held on the PC")
agent.terminate(); agent.waitUntilExit()
check(pump({ !link.bridge.remote && !link.bridge.connected }, timeout: 5), "PC closing returns control to the Mac")
let wrong = WindowsLink(); configure(wrong)
var wrongStatus = ""; wrong.onStatus = { wrongStatus = $0 }
let agent2 = Process(); agent2.executableURL = URL(fileURLWithPath: host); agent2.arguments = [key, String(port + 1)]
let pipe2 = Pipe(); agent2.standardOutput = pipe2; try agent2.run()
var second = ""; pipe2.fileHandleForReading.readabilityHandler = { h in lock.lock(); second += String(data: h.availableData, encoding: .utf8) ?? ""; lock.unlock() }
_ = pump({ false }, timeout: 0.5)
try wrong.connect(host: "127.0.0.1", port: port + 1, key: "FEDCBA9876543210FEDCBA9876543210", startBridge: false)
check(pump({ lock.lock(); defer { lock.unlock() }; return second.contains("clave incorrecta") }), "the PC refuses a Mac with another key")
check(!wrong.bridge.connected, "a wrong key never gets control")
wrong.disconnect(); agent2.terminate()
print("RESULT: \(failures) failures; simulated PC, synthetic events only")
exit(failures == 0 ? 0 : 1)
