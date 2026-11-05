import Foundation
import Network
var failures = 0
func check(_ condition: Bool, _ name: String) { print(condition ? "PASS:" : "FAIL:", name); if !condition { failures += 1 } }
func pump(_ condition: () -> Bool, seconds: Double = 5) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
    return condition()
}
do {
    let key = try newPairingKey()
    var sender = try CursorDatagramCodec(key: key, server: true)
    var receiver = try CursorDatagramCodec(key: key, server: false)
    let original = Data([1,0]) + PointerMessage(action: .move, x: 0.75, y: 0.3).serialize()
    let first = try sender.seal(.cursor, original)
    check(try receiver.open(first)?.1 == original, "authenticated datagram preserves the cursor position")
    check(try receiver.open(first) == nil, "replayed cursor cannot move the pointer")
    let old = try sender.seal(.cursor, original)
    let newest = try sender.seal(.cursor, Data([1,1]) + PointerMessage(action: .move, x: 0.9, y: 0.8).serialize())
    check(try receiver.open(newest) != nil && receiver.open(old) == nil, "out-of-order old positions are discarded")
    var tampered = try sender.seal(.cursor, original); tampered[tampered.count-1] ^= 1
    do { _ = try receiver.open(tampered); check(false, "tampering rejected") } catch { check(true, "tampering rejected") }
    var stranger = try CursorDatagramCodec(key: newPairingKey(), server: false)
    do { _ = try stranger.open(first); check(false, "wrong session key rejected") } catch { check(true, "wrong session key rejected") }
    do { _ = try sender.open(first); check(false, "reflection into reverse direction rejected") } catch { check(true, "reflection into reverse direction rejected") }
    let reply = try receiver.seal(.pong, Data(repeating: 0, count: 8))
    check(try sender.open(reply)?.0 == .pong, "reverse direction uses its own authenticated key")
    do { _ = try receiver.open(Data(repeating: 0, count: 166)); check(false, "oversized datagram rejected") } catch { check(true, "oversized datagram rejected") }
    let tlsKey = try newPairingKey()
    let listener = try NWListener(using: networkParameters(key: tlsKey), on: .any)
    var port: NWEndpoint.Port?; var accepted: Peer?; var ready = false
    listener.stateUpdateHandler = { state in if case .ready = state { port = listener.port } }
    listener.newConnectionHandler = { connection in let peer = Peer(connection, queue: .main); accepted = peer; peer.start() }
    listener.start(queue: .main)
    check(pump({ port != nil }), "video route fixture ready")
    if let port = port {
        let video = Peer(NWConnection(host: "127.0.0.1", port: port, using: try networkParameters(key: tlsKey)), queue: .main)
        video.onReady = { ready = true }; video.start()
        check(pump({ ready }), "authenticated video transport reaches loopback")
        let server = CursorChannel(); let client = CursorChannel()
        var offer: CursorOffer?; var positions = 0; var available = false; var fallbacks = 0; var roundTrips = 0
        client.onReady = { DispatchQueue.main.async { available = true } }
        client.onRoundTrip = { _ in DispatchQueue.main.async { roundTrips += 1 } }
        try server.startServer { value in DispatchQueue.main.async { offer = value } }
        check(pump({ offer != nil }), "UDP cursor service starts")
        if let offer = offer {
            try client.startClient(offer: offer, video: video.connection) { data in
                if (try? PointerMessage(Data(data.dropFirst(2)))) != nil { DispatchQueue.main.async { positions += 1 } }
            }
            server.sample({ var d = Data([1,0]); d.append(PointerMessage(action: .move, x: Double(monotonicNS() % 1_000_000)/1_000_000, y: 0.5).serialize()); return d }, fallback: { _, complete in DispatchQueue.main.async { fallbacks += 1 }; complete() })
            check(pump({ available && positions >= 10 && roundTrips >= 1 }), "real encrypted UDP delivers positions and measured round trips")
            let before = fallbacks
            client.stop()
            check(pump({ fallbacks > before }, seconds: 3), "cursor returns to reliable video when UDP stops responding")
        }
        server.stop(); client.stop(); video.end(); accepted?.end(); listener.cancel()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
} catch { print("ERROR", error); failures += 1 }
print("RESULT", failures, "failures")
exit(failures == 0 ? 0 : 1)
