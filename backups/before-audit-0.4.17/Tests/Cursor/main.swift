import Foundation
import Network
var failures = 0
func check(_ value: Bool, _ name: String) { print(value ? "PASS:" : "FAIL:", name); if !value { failures += 1 } }
func pump(_ condition: () -> Bool, seconds: Double = 10) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while !condition() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
    return condition()
}
func rejects(_ name: String, _ f: () throws -> Void) { do { try f(); check(false,name) } catch { check(true,name) } }
var permission = false, permissionReads = 0
let signal = CursorPermission { permissionReads += 1; return permission }
check(!signal.value(now: 0), "live cursor initially reports absent input permission")
permission = true
for instant in 1...1000 { _ = signal.value(now: UInt64(instant)) }
check(permissionReads == 1, "cursor sampling does not repeatedly query Accessibility")
check(signal.value(now: 500_000_000), "grant becomes visible within half a second without reconnecting")
permission = false
check(!signal.value(now: 1_000_000_000), "revocation updates remote permission without retaining a stale grant")
check(!signal.value(now: 5) && permissionReads == 4, "clock reversal refreshes permission instead of retaining it forever")
let gate = CursorDeliveryGate(); let session = UUID(); gate.reset(session)
var delivered = 0
gate.deliver(session,dedicated: false) { delivered += 1 }
gate.deliver(session,dedicated: true) { delivered += 1 }
gate.deliver(session,dedicated: false) { delivered += 100 }
check(delivered == 2,"video fallback cannot overwrite dedicated cursor")
gate.fallback(session); gate.deliver(session,dedicated: false) { delivered += 1 }
check(delivered == 3,"channel failure restores video fallback")
gate.reset(UUID()); gate.deliver(session,dedicated: true) { delivered += 100 }
check(delivered == 3,"old session cannot move cursor after stop")
let server = CursorChannel(); let client = CursorChannel(); let rejected = CursorChannel()
var offer: CursorOffer?; var ready = false; var badReady = false; var received: [Data] = []
server.onReady = { DispatchQueue.main.async { ready = true } }
rejected.onReady = { DispatchQueue.main.async { badReady = true } }
let dummyVideo = NWConnection(host: "127.0.0.1", port: 1234, using: .tcp)
do {
    rejects("zero cursor port rejected") { _ = try CursorOffer(port: 0,key: newPairingKey()) }
    rejects("short offer rejected") { _ = try CursorOffer(Data([0])) }
    try server.startServer { config in DispatchQueue.main.async { offer = config } }
    check(pump({ offer != nil }),"dedicated encrypted cursor listener ready")
    guard let config = offer else { throw AireError("No cursor offer") }
    let parsed = try CursorOffer(config.data)
    check(parsed.port == config.port && parsed.key == config.key,"cursor credentials roundtrip")
    let named = try CursorOffer(port: config.port, key: config.key, host: "macbook.local")
    check(try CursorOffer(named.data).host == "macbook.local", "authenticated control hostname survives the wire")
    rejects("invalid control hostname rejected") { _ = try CursorOffer(port: config.port, key: config.key, host: "bad host") }
    rejects("trailing cursor offer bytes rejected") { _ = try CursorOffer(named.data + Data([0])) }
    let wrong = try CursorOffer(port: config.port,key: newPairingKey())
    try rejected.startClient(offer: wrong,video: dummyVideo) { _ in }
    _ = pump({ badReady }, seconds: 1)
    check(!badReady,"wrong session key never authenticates cursor")
    rejected.stop()
    try client.startClient(offer: config,video: dummyVideo) { body in DispatchQueue.main.async { received.append(body) } }
    check(pump({ ready }),"matching session authenticates cursor independently")
    let message = PointerMessage(action: .move,x: 0.7,y: 0.2)
    var packet = Data([1,1]); packet.append(message.serialize())
    server.sample({ packet },fallback: { _, done in done() })
    check(pump({ received.count == 1 }),"cursor arrives without any video frame or decoder")
    check(received.first == packet,"cursor position and permission flags preserved")
    _ = pump({ received.count > 1 },seconds: 0.2)
    check(received.count == 1,"stationary cursor does not flood connection")
    var latest = Data([1,0]); latest.append(PointerMessage(action: .move,x: 0.9,y: 0.6).serialize())
    server.sample({ latest },fallback: { _, done in done() })
    check(pump({ received.last == latest }),"newest cursor position is delivered")
    server.stop(); client.stop()
    let count = received.count
    _ = pump({ received.count > count },seconds: 0.2)
    check(received.count == count,"stop cancels cursor timer and connection")
} catch { print("ERROR",error); failures += 1 }
server.stop(); client.stop(); rejected.stop()
let bounded = CursorChannel()
let sampleLock = NSLock(); var sampleCount: UInt32 = 0; var sampling = true
var sent: [Data] = []; var completions: [() -> Void] = []
bounded.sample({
    sampleLock.lock(); defer { sampleLock.unlock() }
    guard sampling else { return nil }
    sampleCount += 1; var data = Data(); data.u32(sampleCount); return data
}, fallback: { data, done in DispatchQueue.main.async { sent.append(data); completions.append(done) } })
check(pump({ sent.count == 1 }), "fallback starts one cursor send")
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
sampleLock.lock(); sampling = false; let sampled = sampleCount; sampleLock.unlock()
check(sent.count == 1 && sampled > 5, "blocked transport retains one latest cursor instead of queuing history")
completions.first?()
check(pump({ sent.count == 2 }), "transport completion sends pending latest cursor")
var latestReader = Reader(sent.last ?? Data())
check((try? latestReader.u32()) == sampled, "fallback skips stale positions after a stall")
bounded.stop()
RunLoop.current.run(until: Date().addingTimeInterval(0.05))
completions.last?()
RunLoop.current.run(until: Date().addingTimeInterval(0.05))
check(sent.count == 2, "late send completion cannot restart stopped cursor")
print("RESULT",failures,"failures; synthetic cursor only, no system events posted")
exit(failures == 0 ? 0 : 1)
