import Foundation
import Network
import CryptoKit

struct CursorOffer {
    let port: UInt16
    let key: String
    let serviceName: String
    init(port: UInt16, key: String, serviceName: String = "") throws {
        guard port > 0 else { throw AireError("Puerto de cursor inválido.") }
        guard serviceName.utf8.count <= 90 else { throw AireError("Servicio de cursor inválido.") }
        self.port = port; self.key = try normalizedKey(key); self.serviceName = serviceName
    }
    init(_ data: Data) throws {
        guard (34...124).contains(data.count) else { throw AireError("Canal de cursor inválido.") }
        var reader = Reader(data)
        let port = try reader.u16()
        guard let key = String(data: try reader.bytes(32), encoding: .utf8), let name = String(data: try reader.rest(), encoding: .utf8) else { throw AireError("Clave de cursor inválida.") }
        try self.init(port: port, key: key, serviceName: name)
    }
    var data: Data { var body = Data(); body.u16(port); body.append(Data(key.utf8)); body.append(Data(serviceName.utf8)); return body }
}

// Direction-specific authenticated packets, with replay protection. The fresh
// session secret is offered only through the authenticated video connection.
struct CursorDatagramCodec {
    private let outgoing: SymmetricKey
    private let incoming: SymmetricKey
    private var sequence: UInt64 = 0
    private var highest: UInt64 = 0
    init(key: String, server: Bool) throws {
        let key = try normalizedKey(key)
        func derive(_ direction: String) -> SymmetricKey {
            SymmetricKey(data: SHA256.hash(data: Data(("PRISON-CURSOR-UDP-v1:" + direction + ":" + key).utf8)))
        }
        outgoing = derive(server ? "sender" : "receiver")
        incoming = derive(server ? "receiver" : "sender")
    }
    mutating func seal(_ kind: Wire.Kind, _ body: Data) throws -> Data {
        guard body.count <= 128, sequence < UInt64.max else { throw AireError("Cursor inválido.") }
        sequence += 1
        var plaintext = Data(); plaintext.u64(sequence); plaintext.append(kind.rawValue); plaintext.append(body)
        guard let packet = try AES.GCM.seal(plaintext, using: outgoing).combined else { throw AireError("No se pudo cifrar el cursor.") }
        return packet
    }
    mutating func open(_ packet: Data) throws -> (Wire.Kind, Data)? {
        guard (37...165).contains(packet.count) else { throw AireError("Cursor inválido.") }
        var reader = Reader(try AES.GCM.open(AES.GCM.SealedBox(combined: packet), using: incoming))
        let received = try reader.u64()
        guard received > highest else { return nil }
        let raw = try reader.bytes(1)
        guard let kind = Wire.Kind(rawValue: raw[0]), [.hello, .cursor, .ping, .pong].contains(kind) else { throw AireError("Cursor inválido.") }
        let body = try reader.rest()
        highest = received
        return (kind, body)
    }
}

// UDP avoids waiting for old video or retransmitting obsolete positions. Clicks,
// keys and video remain on TLS/TCP. Unavailable UDP falls back to the video channel.
final class CursorChannel {
    private let queue = DispatchQueue(label: "PrisonDisplay.cursor", qos: .userInteractive)
    private var listener: NWListener?
    private var connection: NWConnection?
    private var timer: DispatchSourceTimer?
    private var health: DispatchSourceTimer?
    private var generation = UUID()
    private var route = UUID()
    private var codec: CursorDatagramCodec?
    private var server = false
    private var authenticated = false
    private var pending: Data?
    private var sending = false
    private var sendEpoch = UUID()
    private var previous: Data?
    private var lastReceive: UInt64 = 0
    private var nextRetry: UInt64 = 0
    private var reconnect: (() -> Void)?
    private var received: ((Data) -> Void)?
    private var fallbackSend: ((Data, @escaping () -> Void) -> Void)?
    var preferLAN = false
    var onReady: (() -> Void)?
    var onUnavailable: ((String) -> Void)?
    // Diagnostic hook; reports cursor-channel round trips without clock syncing.
    var onRoundTrip: ((Double) -> Void)?
    private func parameters() -> NWParameters {
        let p = NWParameters.udp; p.includePeerToPeer = true; p.serviceClass = .interactiveVoice; return p
    }
    func startServer(offer: @escaping (CursorOffer) -> Void) throws {
        let key = try newPairingKey()
        let codec = try CursorDatagramCodec(key: key, server: true)
        let listener = try NWListener(using: parameters(), on: .any)
        let name = "PrisonCursor-" + UUID().uuidString
        listener.service = NWListener.Service(name: name, type: "_airecursor._udp")
        queue.async {
            self.stopOnQueue(); self.server = true; self.codec = codec
            let token = self.generation; self.listener = listener; self.startHealth()
            listener.stateUpdateHandler = { [weak self] state in
                guard let self = self, self.generation == token else { return }
                if case .ready = state, let port = listener.port?.rawValue,
                   let config = try? CursorOffer(port: port, key: key, serviceName: name) { offer(config) }
                if case .failed = state { self.routeDown("Canal de cursor no disponible.") }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self = self, self.generation == token, self.connection == nil else { connection.cancel(); return }
                self.connect(connection)
            }
            listener.start(queue: self.queue)
        }
    }
    func startClient(offer: CursorOffer, video: NWConnection, receive: @escaping (Data) -> Void) throws {
        guard case let .hostPort(host, _) = video.currentPath?.remoteEndpoint ?? video.endpoint,
              let port = NWEndpoint.Port(rawValue: offer.port) else { throw AireError("No se pudo resolver el canal de cursor.") }
        let codec = try CursorDatagramCodec(key: offer.key, server: false)
        let parameters = self.parameters()
        if preferLAN { parameters.includePeerToPeer = false }
        else if let interface = video.currentPath?.availableInterfaces.first { parameters.requiredInterface = interface }
        let endpoint: NWEndpoint
        if case .service = video.endpoint, !offer.serviceName.isEmpty {
            endpoint = .service(name: offer.serviceName, type: "_airecursor._udp", domain: "local.", interface: preferLAN ? nil : video.currentPath?.availableInterfaces.first)
        } else { endpoint = .hostPort(host: host, port: port) }
        queue.async {
            self.stopOnQueue(); self.codec = codec; self.received = receive
            let token = self.generation
            self.reconnect = { [weak self] in
                guard let self = self, self.generation == token, self.connection == nil else { return }
                self.connect(NWConnection(to: endpoint, using: parameters))
            }
            self.reconnect?(); self.startHealth()
        }
    }
    private func connect(_ connection: NWConnection) {
        self.connection = connection; route = UUID(); let token = route
        lastReceive = monotonicNS(); authenticated = false
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self, self.route == token else { return }
            switch state {
            case .ready:
                if !self.server { self.sendControl(.hello, Wire.hello(role: "cursor-receiver")) }
                self.receive(connection, token: token)
            case .failed, .waiting: self.routeDown("Cursor por vídeo mientras se recupera la red.")
            default: break
            }
        }
        connection.start(queue: queue)
    }
    private func startHealth() {
        let health = DispatchSource.makeTimerSource(queue: queue)
        health.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        health.setEventHandler { [weak self] in
            guard let self = self else { return }
            let now = monotonicNS()
            if self.connection == nil { if now >= self.nextRetry { self.reconnect?() }; return }
            if now - self.lastReceive > 1_000_000_000 { self.routeDown("Cursor por vídeo mientras se recupera la red."); return }
            if !self.authenticated {
                if !self.server { self.sendControl(.hello, Wire.hello(role: "cursor-receiver")) }
            } else { var ping = Data(); ping.u64(now); self.sendControl(.ping, ping) }
        }
        self.health = health; health.resume()
    }
    private func receive(_ connection: NWConnection, token: UUID) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self = self, self.route == token else { return }
            if let data = data {
                do {
                    if let (kind, body) = try self.codec?.open(data) {
                        if kind == .hello {
                            _ = try Wire.checkHello(body, expected: self.server ? "cursor-receiver" : "cursor-sender")
                            self.lastReceive = monotonicNS()
                            if self.server { self.sendControl(.hello, Wire.hello(role: "cursor-sender")) }
                            if !self.authenticated { self.authenticated = true; self.previous = nil; self.sending = false; self.sendEpoch = UUID(); self.onReady?(); self.flush() }
                        } else if self.authenticated {
                            if kind == .cursor && !self.server {
                                guard body.count == PointerMessage.encodedSize + 2, body[0] <= 1, body[1] <= 1 else { throw AireError("Cursor inválido.") }
                                let position = try PointerMessage(Data(body.dropFirst(2)))
                                guard position.action == .move else { throw AireError("Cursor inválido.") }
                                self.lastReceive = monotonicNS(); self.received?(body)
                            } else if (kind == .ping || kind == .pong), body.count == 8 {
                                self.lastReceive = monotonicNS()
                                if kind == .ping { self.sendControl(.pong, body) }
                                else { var r = Reader(body); let sent = try r.u64(); let now = monotonicNS(); if sent <= now { self.onRoundTrip?(Double(now-sent)/1e6) } }
                            }
                        }
                    }
                } catch { /* Invalid, replayed or unauthenticated UDP cannot move the cursor. */ }
            }
            if error != nil { self.routeDown("Cursor por vídeo mientras se recupera la red.") }
            else { self.receive(connection, token: token) }
        }
    }
    private func sendControl(_ kind: Wire.Kind, _ body: Data) {
        guard let connection = connection, let data = try? codec?.seal(kind, body) else { return }
        let token = route
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self = self, self.route == token else { return }
            if let error = error { self.routeDown("Canal de cursor no disponible: \(error)") }
        })
    }
    func sample(_ producer: @escaping () -> Data?, fallback: @escaping (Data, @escaping () -> Void) -> Void) {
        queue.async {
            self.timer?.cancel(); self.previous = nil; self.fallbackSend = fallback
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in
                guard let self = self, let body = producer(), body != self.previous else { return }
                self.previous = body; self.pending = body; self.flush()
            }
            self.timer = timer; timer.resume()
        }
    }
    private func flush() {
        guard !sending, let data = pending else { return }
        pending = nil; sending = true; let token = generation; let routeToken = route; sendEpoch = UUID(); let epoch = sendEpoch
        let complete: () -> Void = { [weak self] in
            self?.queue.async { [weak self] in
                guard let self = self, self.generation == token, self.sendEpoch == epoch else { return }
                self.sending = false; self.flush()
            }
        }
        if authenticated, let connection = connection, let packet = try? codec?.seal(.cursor, data) {
            connection.send(content: packet, completion: .contentProcessed { [weak self] error in
                guard let self = self, self.generation == token else { return }
                if let error = error, self.route == routeToken { self.routeDown("Canal de cursor no disponible: \(error)") }
                complete()
            })
        } else if let fallback = fallbackSend { fallback(data, complete) }
        else { sending = false }
    }
    private func routeDown(_ reason: String) {
        let old = connection; connection = nil; route = UUID()
        old?.stateUpdateHandler = nil; old?.cancel()
        let wasActive = authenticated; authenticated = false; previous = nil; sending = false; sendEpoch = UUID()
        nextRetry = monotonicNS() + 250_000_000
        if wasActive || !server { onUnavailable?(reason) }
    }
    func stop() { queue.async { self.stopOnQueue() } }
    private func stopOnQueue() {
        generation = UUID(); route = UUID(); timer?.cancel(); timer = nil; health?.cancel(); health = nil
        listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil; listener?.cancel(); listener = nil
        let old = connection; connection = nil; old?.stateUpdateHandler = nil; old?.cancel()
        pending = nil; previous = nil; sending = false; sendEpoch = UUID(); authenticated = false; received = nil; fallbackSend = nil; codec = nil; reconnect = nil; server = false
    }
}

// Prevent video-fallback positions from overwriting fresher dedicated positions.
// The token also discards messages belonging to a session that has stopped.
final class CursorDeliveryGate {
    private let lock = NSLock()
    private var session = UUID()
    private var dedicated = false
    func reset(_ token: UUID) { lock.lock(); session = token; dedicated = false; lock.unlock() }
    func fallback(_ token: UUID) { lock.lock(); if session == token { dedicated = false }; lock.unlock() }
    func deliver(_ token: UUID, dedicated source: Bool, _ callback: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard session == token else { return }
        if source { dedicated = true } else if dedicated { return }
        callback()
    }
}
