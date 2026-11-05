import Foundation
import Network
var failures = 0
func check(_ condition: Bool, _ name: String) { print("\(condition ? "PASS" : "FAIL"): \(name)"); if !condition { failures += 1 } }
func pump(until: () -> Bool, seconds: Double = 10) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while !until() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    return until()
}
func rejects(_ name: String, _ body: () throws -> Void) { do { try body(); check(false, name) } catch { check(true, name) } }
do {
    let key = try newPairingKey()
    let link = try ConnectionLink(host: "macbook.local", port: 54321, key: key)
    check(!discoveryParameters().includePeerToPeer, "automatic Bonjour discovery uses the shared network without peer Wi-Fi")
    let lan = try networkParameters(key: key)
    check(!lan.includePeerToPeer, "video and auxiliary listeners avoid peer Wi-Fi by default")
    check(configureStreamRoute(lan, endpoint: link.hostEndpoint) && !lan.includePeerToPeer,
          "authenticated Bonjour hostname first tries IPv4 on the shared LAN")
    let v6 = try networkParameters(key: key)
    check(!configureStreamRoute(v6, endpoint: link.hostEndpoint, preferIPv4: false) && !v6.includePeerToPeer,
          "IPv6 hostname retry keeps the shared LAN")
    check(!prefersSharedLAN(.service(name: "test", type: Wire.service, domain: "local.", interface: nil)),
          "unresolved service is not assumed to be a shared LAN")
    let parsed = try ConnectionLink(link.url)
    check(parsed.host == link.host && parsed.port == link.port && parsed.key == key, "connection link roundtrip")
    rejects("link duplicate fields") { _ = try ConnectionLink(URL(string: link.url.absoluteString + "&key=" + key)!) }
    rejects("link wrong scheme") { _ = try ConnectionLink(URL(string: "https://example.com/connect")!) }
    rejects("link bad version") { _ = try ConnectionLink(URL(string: link.url.absoluteString.replacingOccurrences(of: AppVersion.current, with: "99.0.0"))!) }
    rejects("link zero port") { _ = try ConnectionLink(host: "macbook.local", port: 0, key: key) }
    rejects("link wrong key") { _ = try ConnectionLink(host: "macbook.local", port: 22, key: "0000") }
    let serviceLink = try ConnectionLink(host: "macbook.local", port: 54321, key: key, serviceName: "AireDisplay-test")
    check(try ConnectionLink(serviceLink.url).serviceName == "AireDisplay-test", "Bonjour service survives manual link roundtrip")
    rejects("unknown link field") { _ = try ConnectionLink(URL(string: link.url.absoluteString + "&extra=x")!) }
    rejects("empty service") { _ = try ConnectionLink(host: "macbook.local", port: 54321, key: key, serviceName: "") }
    let remembered = try TrustedProfile(serviceLink)
    check(try TrustedProfile.decode(remembered.encoded()) == remembered, "remembered connection validates and roundtrips")
    rejects("manual connection without Bonjour cannot persist") { _ = try TrustedProfile(link) }
    rejects("oversized stored connection rejected") { _ = try TrustedProfile.decode(Data(repeating: 0, count: 8193)) }
    var invalidProfile = try JSONSerialization.jsonObject(with: remembered.encoded()) as! [String: Any]; invalidProfile["schema"] = 99
    rejects("incompatible stored schema rejected") { _ = try TrustedProfile.decode(JSONSerialization.data(withJSONObject: invalidProfile)) }
    let q = DispatchQueue.main
    let tls = try NWListener(using: networkParameters(key: key), on: .any)
    let streamService = "AireDisplay-test-" + UUID().uuidString
    tls.service = NWListener.Service(name: streamService, type: Wire.service)
    var tlsReady = false; var streamPeer: Peer?; var streamConnected = false
    tls.stateUpdateHandler = { if case .ready = $0 { tlsReady = true } }
    tls.newConnectionHandler = { c in
        let p = Peer(c, queue: q); streamPeer = p
        p.onReady = { p.send(.hello, Wire.hello(role: "sender")) }
        p.start()
    }
    tls.start(queue: q); check(pump(until: { tlsReady }), "TLS listener ready")
    // Catalina's fresh Options wrapper reports .any after setting .v4.
    // Verify the actual transport restriction, with an IPv6 positive control.
    let ipv6Control = Peer(NWConnection(host: "::1", port: tls.port!, using: try networkParameters(key: key)), queue: q)
    var ipv6Works = false
    ipv6Control.onReady = { ipv6Works = true }
    ipv6Control.start(); check(pump(until: { ipv6Works }), "IPv6 loopback is available for the route negative control")
    ipv6Control.end(); streamPeer?.end()
    let sixParameters = try networkParameters(key: key)
    let sixOptions = sixParameters.defaultProtocolStack.internetProtocol as! NWProtocolIP.Options
    sixOptions.version = .v6; sixParameters.defaultProtocolStack.internetProtocol = sixOptions
    let sixDNS = Peer(NWConnection(host: "localhost", port: tls.port!, using: sixParameters), queue: q)
    var sixReady = false, sixSelected = false
    sixDNS.onReady = {
        sixReady = true
        if case let .hostPort(host, _) = sixDNS.connection.currentPath?.remoteEndpoint, case .ipv6 = host { sixSelected = true }
    }
    sixDNS.start(); check(pump(until: { sixReady }) && sixSelected, "IPv6 DNS control selects IPv6 on dual-stack localhost")
    sixDNS.end(); streamPeer?.end()
    let ipv4Control = Peer(NWConnection(host: "localhost", port: tls.port!, using: lan), queue: q)
    var ipv4Works = false, fourSelected = false
    ipv4Control.onReady = {
        ipv4Works = true
        if case let .hostPort(host, _) = ipv4Control.connection.currentPath?.remoteEndpoint, case .ipv4 = host { fourSelected = true }
    }
    ipv4Control.start(); check(pump(until: { ipv4Works }) && fourSelected, "LAN configuration actually resolves dual-stack localhost to IPv4")
    ipv4Control.end(); streamPeer?.end()
    let server = PairingServer(queue: q)
    var senderCode: String?; var receiverCode: String?; var senderApprove: ((Bool) -> Void)?; var receiverApprove: ((Bool) -> Void)?
    var accepted = false
    func approveIfEqual() {
        guard !accepted, let a = senderCode, let b = receiverCode else { return }
        check(a == b && a.count == 6, "ECDH verification codes match")
        accepted = true; senderApprove?(a == b); receiverApprove?(a == b)
    }
    server.onConfirm = { _, code, done in senderCode = code; senderApprove = done; approveIfEqual() }
    try server.start(streamPort: tls.port!.rawValue, streamKey: key, serviceName: streamService)
    check(pump(until: { server.isReady }), "automatic pairing listener ready")
    let browser = NWBrowser(for: .bonjour(type: PairingServer.service, domain: nil), using: discoveryParameters())
    var discovered: NWEndpoint?
    browser.browseResultsChangedHandler = { results, _ in
        discovered = results.map { $0.endpoint }.first { endpoint in
            if case .service(let name, _, _, _) = endpoint { return name == (Host.current().localizedName ?? "MacBook") }
            return false
        }
    }
    browser.start(queue: q)
    check(pump(until: { discovered != nil }), "Bonjour discovers the available MacBook without an address")
    let client = PairingClient(queue: q); var credentials: ConnectionLink?; var ended: String?
    client.onConfirm = { _, code, done in receiverCode = code; receiverApprove = done; approveIfEqual() }
    client.onConnected = { credentials = $0 }; client.onStatus = { ended = $0 }
    client.start(endpoint: discovered ?? .hostPort(host: "127.0.0.1", port: server.port!))
    check(pump(until: { credentials != nil }), "approval transfers encrypted connection credentials")
    check(credentials?.key == key && credentials?.port == tls.port!.rawValue, "automatic credentials match TLS endpoint")
    check(credentials?.host == localConnectionHostname(), "automatic stream preserves Bonjour hostname instead of scoped IPv6")
    check(credentials?.serviceName == streamService, "encrypted credentials carry Bonjour stream service")
    if let credentials = credentials {
        let resolver = VideoRouteResolver()
        var selectedRoute: NWEndpoint?
        resolver.resolve(credentials.endpoint, queue: q) { selectedRoute = $0 }
        check(pump(until: { selectedRoute != nil }), "preferred route resolution completes with router fallback")
        let p = Peer(NWConnection(to: selectedRoute ?? credentials.endpoint, using: try networkParameters(key: credentials.key)), queue: q)
        p.onPacket = { kind, data in if kind == .hello, (try? Wire.checkHello(data, expected: "sender")) != nil { streamConnected = true } }
        p.start(); check(pump(until: { streamConnected }), "automatically paired client authenticates stream TLS")
        p.end()
    } else { print("PAIR ERROR", ended as Any) }
    client.stop(); streamPeer?.end(); tls.cancel()
    var denied = false
    server.onConfirm = { _, _, done in denied = true; done(false) }
    let deniedClient = PairingClient(queue: q); var denialMessage = ""; var wronglyConnected = false
    deniedClient.onConfirm = { _, _, done in done(true) }
    deniedClient.onStatus = { denialMessage = $0 }
    deniedClient.onConnected = { _ in wronglyConnected = true }
    deniedClient.start(endpoint: .hostPort(host: "127.0.0.1", port: server.port!))
    check(pump(until: { denied && denialMessage.contains("rechazada") }), "sender rejection reaches receiver")
    check(!wronglyConnected, "rejected request never receives stream credentials")
    deniedClient.stop()
    server.stop(); browser.cancel()
    let canceledRoute = VideoRouteResolver(); var staleRoute = false
    canceledRoute.resolve(.service(name: "AireDisplay-absent-test", type: Wire.service, domain: "local.", interface: nil), queue: q) { _ in staleRoute = true }
    canceledRoute.cancel()
    _ = pump(until: { staleRoute }, seconds: 2.2)
    check(!staleRoute, "canceled route cannot reconnect after stop")
    print("RESULT: \(failures) failures")
} catch { print("FAIL", error); failures += 1 }
exit(failures == 0 ? 0 : 1)
