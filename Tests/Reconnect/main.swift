import AppKit
import Network
func pump(_ condition: () -> Bool, timeout: Double = 8) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
    return condition()
}
var failures = 0
func check(_ condition: Bool, _ name: String) { print(condition ? "PASS: \(name)" : "FAIL: \(name)"); if !condition { failures += 1 } }
let key = try newPairingKey()
let listener = try NWListener(using: networkParameters(key: key), on: .any)
var ready = false
var server: Peer?
var connections = 0
var hellos = 0
var cursorPackets = 0
var receivedPixels = 0
var peerNames: [String] = []
var failRemote = false
var remoteReason = false
var vectors = Reader(try Data(contentsOf: URL(fileURLWithPath: "build/CoreTests-vectors.dat")))
let frameSize = Int(try vectors.u32()); _ = try vectors.bytes(5)
let firstFrame = try vectors.bytes(frameSize)
var stopSeen = false
let receiver = ReceiverEngine()
receiver.retryDelay = { _ in 0.08 }
receiver.onPeerConnected = { name in DispatchQueue.main.async { peerNames.append(name) } }
receiver.onPixel = { _, done in DispatchQueue.main.async { receivedPixels += 1; done(.accepted) } }
receiver.onStatus = { status in print("STATUS:",status); if status.contains("El otro Mac: prueba de permiso") { remoteReason = true }; if status == "Desconectado." { stopSeen = true } }
receiver.onCursor = { _, _, visible, _ in if visible { DispatchQueue.main.async { cursorPackets += 1 } } }
listener.stateUpdateHandler = { state in if case .ready = state { ready = true } }
listener.newConnectionHandler = { c in
    connections += 1
    let p = Peer(c, queue: .main); server = p
    p.onReady = { p.send(.hello, Wire.hello(role: "sender")) }
    p.onPacket = { kind, _ in if kind == .hello {
        hellos += 1
        if failRemote { p.send(.failure, Data("prueba de permiso".utf8)); return }
        var data = Data([1,1]); data.append(PointerMessage(action: .move, x: 0.3, y: 0.4).serialize())
        p.send(.cursor, data); p.send(.video, firstFrame)
    } }
    p.start()
}
listener.start(queue: .main)
check(pump({ ready }), "TLS listener ready")
try receiver.connect(endpoint: .hostPort(host: "127.0.0.1", port: listener.port!), key: key)
check(pump({ cursorPackets == 1 && receivedPixels == 1 }), "authenticated receiver session starts")
check(receiver.queue.sync { receiver.streamActivity.isActive }, "receiving holds a precise streaming activity")
for n in 2...4 {
    server?.end("Simulated network cut")
    check(pump({ cursorPackets >= n && receivedPixels >= n }), "receiver reconnects automatically after cut \(n-1)")
}
check(peerNames.count >= 4 && peerNames.allSatisfy { $0 == (Host.current().localizedName ?? "Este Mac") }, "every authenticated reconnect refreshes the peer name")
server?.end("Cut before explicit stop")
receiver.stop()
check(pump({ stopSeen }), "explicit disconnect observed")
check(!receiver.queue.sync { receiver.streamActivity.isActive }, "manual disconnect releases receiver activity")
let count = connections
RunLoop.current.run(until: Date().addingTimeInterval(0.35))
check(connections == count, "manual disconnect cancels scheduled reconnect")
try receiver.connect(endpoint: .hostPort(host: "127.0.0.1", port: listener.port!), key: key, previouslyApproved: true)
check(pump({ receivedPixels >= 5 }), "remembered approved connection can reopen")
receiver.stop(); check(pump({ stopSeen }), "stop remembered session")
RunLoop.current.run(until: Date().addingTimeInterval(0.1))
failRemote = true
try receiver.connect(endpoint: .hostPort(host: "127.0.0.1", port: listener.port!), key: key)
check(pump({ remoteReason }), "remote capture error reaches receiver")
check(pump({ !receiver.queue.sync { receiver.streamActivity.isActive } }), "permanent remote failure releases receiver activity")
let failedCount = connections
RunLoop.current.run(until: Date().addingTimeInterval(0.35))
check(connections == failedCount, "permanent capture error does not loop reconnection")
failRemote = false
let wrongKey = try newPairingKey()
try receiver.connect(endpoint: .hostPort(host: "127.0.0.1", port: listener.port!), key: wrongKey)
let before = hellos
RunLoop.current.run(until: Date().addingTimeInterval(0.6))
check(hellos == before, "wrong credential cannot authenticate or trigger an approved session")
let reservedPort = listener.port!
receiver.stop(); server?.end(); listener.cancel()
RunLoop.current.run(until: Date().addingTimeInterval(0.15))
let offlineListener = try NWListener(using: networkParameters(key: key), on: reservedPort)
offlineListener.newConnectionHandler = { c in
    let p = Peer(c, queue: .main); server = p
    p.onReady = { p.send(.hello, Wire.hello(role: "sender")); p.send(.video, firstFrame) }; p.start()
}
let offlinePixels = receivedPixels
try receiver.connect(endpoint: .hostPort(host: "127.0.0.1", port: reservedPort), key: key, previouslyApproved: true)
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { offlineListener.start(queue: .main) }
check(pump({ receivedPixels > offlinePixels }, timeout: 15), "remembered receiver waits for sender opened later")
receiver.stop(); server?.end(); offlineListener.cancel()
RunLoop.current.run(until: Date().addingTimeInterval(0.15))
let sleepingListener = try NWListener(using: networkParameters(key: key), on: .any)
var sleepingPort: NWEndpoint.Port?
var attempts: [Int] = []
receiver.retryDelay = { attempt in DispatchQueue.main.async { attempts.append(attempt) }; return 0.02 }
sleepingListener.stateUpdateHandler = { if case .ready = $0 { sleepingPort = sleepingListener.port } }
sleepingListener.newConnectionHandler = { connection in
    let p = Peer(connection, queue: .main); server = p
    p.onReady = { p.send(.hello, Wire.hello(role: "sender")) }
    p.onPacket = { kind, _ in if kind == .hello { DispatchQueue.main.asyncAfter(deadline: .now()+0.05) { p.end("Temporarily unavailable screen") } } }
    p.start()
}
sleepingListener.start(queue: .main)
check(pump({ sleepingPort != nil }), "temporary no-image source listener starts")
try receiver.connect(endpoint: .hostPort(host: "127.0.0.1", port: sleepingPort!), key: key, previouslyApproved: true)
check(pump({ attempts.count >= 3 }) && Array(attempts.prefix(3)) == [0,1,2], "authenticated greetings without images preserve reconnect backoff")
receiver.stop(); server?.end(); sleepingListener.cancel()
print("RESULT: \(failures) failures")
exit(failures == 0 ? 0 : 1)
