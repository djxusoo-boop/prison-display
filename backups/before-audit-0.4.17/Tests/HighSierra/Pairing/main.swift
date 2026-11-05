import Foundation
#if !LEGACY
import Network
#endif
setbuf(stdout, nil)
let queue = DispatchQueue.main
let fixtureKey = "00112233445566778899AABBCCDDEEFF"
let fixturePort: UInt16 = 55111
let serviceType = "_prisoncheck._tcp"
func pump(_ done: () -> Bool, seconds: Double = 45) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while !done() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
    return done()
}
if CommandLine.arguments[1] == "server" {
    let server = PairingServer(queue: queue)
    server.onConfirm = { _, code, accept in print("CODE", code); accept(true) }
    try server.start(streamPort: fixturePort, streamKey: fixtureKey)
    guard pump({ server.isReady }, seconds: 10), let port = server.port else { exit(1) }
    let beacon = try NWListener(using: discoveryParameters(), on: .any)
    let name = "Prison-check-" + UUID().uuidString
    beacon.service = NWListener.Service(name: name, type: serviceType)
    var peers: [Peer] = []
    beacon.newConnectionHandler = { connection in
        let peer = Peer(connection, queue: queue); peers.append(peer)
        peer.onReady = { var data = Data(); data.u16(port.rawValue); peer.send(.hello, data) }
        peer.start()
    }
    beacon.stateUpdateHandler = { state in if case .ready = state { print("READY", name) } }
    beacon.start(queue: queue)
    _ = pump({ false })
    beacon.cancel(); server.stop(); peers.forEach { $0.end() }
} else {
    let host = CommandLine.arguments[2], name = CommandLine.arguments[3]
    let browser = NWBrowser(for: .bonjour(type: serviceType, domain: "local."), using: discoveryParameters())
    let client = PairingClient(queue: queue)
    var discovered = false, success = false, ended = false, peer: Peer?
    client.onConfirm = { _, code, accept in print("CODE", code); accept(true) }
    client.onConnected = { link in
        success = link.port == fixturePort && link.key == fixtureKey
        print("PAIR", success ? "PASS" : "FAIL"); ended = true
    }
    client.onStatus = { print("STATUS", $0) }
    browser.browseResultsChangedHandler = { results, _ in
        guard !discovered, let found = results.first(where: { result in
            if case .service(let candidate, _, _, _) = result.endpoint { return candidate == name }; return false
        }) else { return }
        discovered = true; print("DISCOVERY PASS")
        let connection = NWConnection(to: found.endpoint, using: discoveryParameters())
        let beacon = Peer(connection, queue: queue); peer = beacon
        beacon.onPacket = { kind, data in
            if kind == .hello { do {
                var reader = Reader(data); let port = try reader.u16()
                client.start(endpoint: .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!))
            } catch { ended = true } }
        }
        beacon.start()
    }
    browser.start(queue: queue)
    let completed = pump({ ended })
    browser.cancel(); client.stop(); peer?.end()
    print("RESULT", completed && discovered && success ? "PASS" : "FAIL", "real Bonjour and cross-runtime encrypted pairing; fixture credentials only")
    exit(completed && discovered && success ? 0 : 1)
}
