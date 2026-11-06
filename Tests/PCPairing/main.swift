import AppKit
import Network
// Pairing with the real PC agent (compiled for macOS): discovery, code, key.
setbuf(stdout, nil)
var failures = 0
func check(_ value: Bool, _ name: String) { print(value ? "PASS:" : "FAIL:", name); if !value { failures += 1 } }
func pump(_ condition: () -> Bool, timeout: Double = 8) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    return condition()
}
let host = CommandLine.arguments[1]
let key = "00112233445566778899AABBCCDDEEFF"
let base = UInt16(43000 + Int(getpid() % 1500))
var output: [String] = []; let lock = NSLock()
func launch(_ decision: String, offset: UInt16) throws -> Process {
    let agent = Process(); agent.executableURL = URL(fileURLWithPath: host)
    agent.arguments = [key, String(base + offset), decision, String(base + offset + 1), String(base + 900)]
    let pipe = Pipe(); agent.standardOutput = pipe; agent.standardInput = Pipe()
    var partial = ""
    pipe.fileHandleForReading.readabilityHandler = { h in
        lock.lock(); partial += String(data: h.availableData, encoding: .utf8) ?? ""
        while let n = partial.firstIndex(of: "\n") { output.append(String(partial[..<n])); partial = String(partial[partial.index(after: n)...]) }
        lock.unlock()
    }
    try agent.run(); return agent
}
func lines() -> [String] { lock.lock(); defer { lock.unlock() }; return output }
let agent = try launch("accept", offset: 0)
var found: [FoundPC]?
PCDiscovery.scan(seconds: 3, port: base + 900) { found = $0 }
check(pump({ found != nil }), "scan finishes")
let pc = found?.first
check(pc?.name == "Torre simulada" && pc?.inputPort == base && pc?.pairingPort == base + 1, "the PC announces itself with its address and ports (\(String(describing: found)))")
check(FoundPC(announcement: "PRISON-PC/1|x|1.0|0|1", from: "1.2.3.4") == nil && FoundPC(announcement: "OTRA|a|1.0|1|2", from: "1.2.3.4") == nil, "malformed announcements are ignored")
var macCode: String?, result: Result<(key: String, port: UInt16, name: String), Error>?
let pairing = PCPairing()
pairing.start(host: "127.0.0.1", port: base + 1, confirm: { name, code, done in macCode = code; done(name == "Torre simulada") }) { result = $0 }
check(pump({ result != nil }), "pairing completes")
let pcCode = lines().first { $0.hasPrefix("PAIR ") }?.split(separator: " ").last.map(String.init)
check(macCode != nil && macCode == pcCode, "both computers show the same 6-digit code (\(macCode ?? "-"))")
if case .success(let got) = result { check(got.key == key && got.port == UInt16(base) && got.name == "Torre simulada", "the PC key arrives encrypted after both confirm") }
else { check(false, "the PC key arrives encrypted after both confirm (\(String(describing: result)))") }
// The key from pairing opens the encrypted input connection.
if case .success(let got) = result {
    let link = WindowsLink(); link.displays = { [CGRect(x: 0, y: 0, width: 100, height: 100)] }
    try link.connect(host: "127.0.0.1", port: got.port, key: got.key, startBridge: false)
    check(pump({ link.bridge.connected }), "the paired key connects without typing anything")
    link.disconnect()
}
agent.terminate(); agent.waitUntilExit()
let refusing = try launch("reject", offset: 10)
var refused: Result<(key: String, port: UInt16, name: String), Error>?
PCPairing().start(host: "127.0.0.1", port: base + 11, confirm: { _, _, done in done(true) }) { refused = $0 }
check(pump({ refused != nil }), "refusal finishes")
if case .failure = refused! { check(true, "rejecting on the PC never reveals the key") } else { check(false, "rejecting on the PC never reveals the key") }
var cancelled: Result<(key: String, port: UInt16, name: String), Error>?
let refusing2 = try launch("accept", offset: 20)
PCPairing().start(host: "127.0.0.1", port: base + 21, confirm: { _, _, done in done(false) }) { cancelled = $0 }
check(pump({ cancelled != nil }), "cancel finishes")
if case .failure = cancelled! { check(true, "a different code (rejected on the Mac) never reveals the key") } else { check(false, "a different code (rejected on the Mac) never reveals the key") }
refusing.terminate(); refusing2.terminate()
print("RESULT: \(failures) failures; simulated PC, no input posted")
exit(failures == 0 ? 0 : 1)
