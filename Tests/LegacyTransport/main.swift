import Foundation
#if !LEGACY
import Network
import CryptoKit
#endif
setbuf(stdout, nil)
let arguments = CommandLine.arguments
let queue = DispatchQueue.main
let fixtureKey = "00112233445566778899AABBCCDDEEFF"
func pump(_ condition: () -> Bool, seconds: Double = 30) -> Bool {
    let until = Date().addingTimeInterval(seconds)
    while !condition() && Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
    return condition()
}
let role = arguments[1]
if role == "server" {
    let listener = try NWListener(using: networkParameters(key: fixtureKey), on: .any)
    var peers: [Peer] = []
    listener.stateUpdateHandler = { state in if case .ready = state { print("READY", listener.port!.rawValue) } }
    listener.newConnectionHandler = { connection in
        let peer = Peer(connection, queue: queue); peers.append(peer)
        peer.onReady = { peer.send(.hello, Wire.hello(role: "sender")) }
        peer.onPacket = { kind, data in
            do {
                if kind == .hello { _ = try Wire.checkHello(data, expected: "receiver") }
                else if kind == .video { peer.send(.ack, Data(SHA256.hash(data: data))) }
                else { throw AireError("Unexpected fixture packet") }
            } catch { peer.end("\(error)") }
        }
        peer.onEnd = { reason in print("END", reason); peers.removeAll { $0 === peer } }
        peer.start()
    }
    listener.start(queue: queue)
    _ = pump({ false }, seconds: 150)
    listener.cancel(); peers.forEach { $0.end() }
} else {
    let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(arguments[2]), port: NWEndpoint.Port(rawValue: UInt16(arguments[3])!)!)
    let wrong = role == "wrong-key"
    let peer = Peer(NWConnection(to: endpoint, using: try networkParameters(key: wrong ? "FFEEDDCCBBAA99887766554433221100" : fixtureKey)), queue: queue)
    var success = false, completed = false, failure: String?, ready = false
    var count = 0, began: UInt64 = 0, durations: [Double] = []
    let payload = Data((0..<1_048_576).map { UInt8(truncatingIfNeeded: $0) })
    let expected = Data(SHA256.hash(data: payload))
    peer.onReady = { ready = true; peer.send(.hello, Wire.hello(role: "receiver")) }
    peer.onPacket = { kind, data in
        do {
            if kind == .hello { _ = try Wire.checkHello(data, expected: "sender"); began = monotonicNS(); peer.send(.video, payload) }
            else if kind == .ack {
                guard data == expected else { throw AireError("Payload changed across transport") }
                durations.append(Double(monotonicNS()-began)/1_000_000); count += 1
                if count == 10 { success = true; completed = true; peer.end("Fixture complete") }
                else { began = monotonicNS(); peer.send(.video, payload) }
            }
        } catch { failure = "\(error)"; completed = true }
    }
    peer.onEnd = { reason in if !success { failure = reason }; completed = true }
    peer.start()
    let ended = pump({ completed }, seconds: 90)
    if wrong {
        print("RESULT wrong-key", ended && !ready ? "PASS" : "FAIL"); peer.end(); exit(ended && !ready ? 0 : 1)
    }
    durations.sort()
    print("RESULT", success && ended ? "PASS" : "FAIL", "payloads", count, "MiB", count, "medianMS", durations.isEmpty ? -1 : durations[durations.count/2], "error", failure ?? "none")
    peer.end(); exit(success && ended ? 0 : 1)
}
