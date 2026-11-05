import Foundation
import Network

struct CursorOffer {
    let port: UInt16
    let key: String
    let serviceName: String
    let host: String
    init(port: UInt16, key: String, serviceName: String = "", host: String = "") throws {
        guard port > 0 else { throw AireError("Puerto de cursor inválido.") }
        guard serviceName.utf8.count <= 90 else { throw AireError("Servicio de cursor inválido.") }
        guard host.utf8.count <= 253, !host.contains(where: { $0.isWhitespace }) else { throw AireError("Dirección de control inválida.") }
        self.port = port; self.key = try normalizedKey(key); self.serviceName = serviceName; self.host = host
    }
    init(_ data: Data) throws {
        guard (38...381).contains(data.count) else { throw AireError("Canal de cursor inválido.") }
        var reader = Reader(data)
        let port = try reader.u16()
        let keyData = try reader.bytes(32)
        let hostLength = try reader.u16(); let hostData = try reader.bytes(Int(hostLength))
        let nameLength = try reader.u16(); let nameData = try reader.bytes(Int(nameLength))
        guard let key = String(data: keyData, encoding: .utf8),
              let host = String(data: hostData, encoding: .utf8),
              let name = String(data: nameData, encoding: .utf8),
              try reader.rest().isEmpty else { throw AireError("Clave de cursor inválida.") }
        try self.init(port: port, key: key, serviceName: name, host: host)
    }
    var data: Data { var body = Data(); body.u16(port); body.append(Data(key.utf8)); body.u16(UInt16(host.utf8.count)); body.append(Data(host.utf8)); body.u16(UInt16(serviceName.utf8.count)); body.append(Data(serviceName.utf8)); return body }
}

// This queue never encodes or decodes video. Session credentials arrive over the
// already authenticated video connection and are fresh for every session.
final class CursorChannel {
    private let queue = DispatchQueue(label: "PrisonDisplay.cursor", qos: .userInteractive)
    private var listener: NWListener?
    private var peer: Peer?
    private var timer: DispatchSourceTimer?
    private var generation = UUID()
    private var authenticated = false
    private var pending: Data?
    private var sending = false
    private var previous: Data?
    private var received: ((Data) -> Void)?
    private var fallbackSend: ((Data, @escaping () -> Void) -> Void)?
    private let readyLock = NSLock()
    private var readySnapshot = false
    var isReady: Bool { readyLock.lock(); defer { readyLock.unlock() }; return readySnapshot }
    private func setReady(_ value: Bool) { readyLock.lock(); readySnapshot = value; readyLock.unlock() }
    var onInput: ((Wire.Kind, Data) -> Void)?
    var onReady: (() -> Void)?
    var onUnavailable: ((String) -> Void)?
    func startServer(host: String = "", offer: @escaping (CursorOffer) -> Void) throws {
        let key = try newPairingKey()
        let parameters = try networkParameters(key: key); parameters.serviceClass = .interactiveVoice
        let listener = try NWListener(using: parameters, on: .any)
        // Its endpoint is delivered through the authenticated video socket.
        // Publishing another peer-to-peer service keeps AWDL discovery active.
        queue.async {
            self.stopOnQueue(); let token = self.generation; self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                guard let self = self, self.generation == token else { return }
                if case .ready = state, let port = listener.port?.rawValue, let config = try? CursorOffer(port: port, key: key, host: host) { offer(config) }
                if case .failed = state { self.stopOnQueue() }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self = self, self.generation == token, self.peer == nil else { connection.cancel(); return }
                let peer = Peer(connection, queue: self.queue); self.peer = peer
                peer.onReady = { peer.send(.hello, Wire.hello(role: "cursor-sender")) }
                peer.onPacket = { [weak self, weak peer] kind, data in
                    guard let self = self, self.generation == token, let peer = peer else { return }
                    do {
                        if kind == .hello, !self.authenticated {
                            _ = try Wire.checkHello(data, expected: "cursor-receiver")
                            self.authenticated = true; self.setReady(true); self.previous = nil; self.onReady?()
                        } else if self.authenticated, [.pointer, .keyboard, .desktopPointer, .desktopKeyboard, .desktopControl].contains(kind) {
                            self.onInput?(kind, data)
                        } else { throw AireError("Mensaje de control inesperado.") }
                    } catch { peer.end("\(error)") }
                }
                peer.onEnd = { [weak self] reason in
                    guard let self = self, self.generation == token else { return }
                    let wasReady = self.authenticated
                    self.peer = nil; self.authenticated = false; self.setReady(false); self.sending = false; self.previous = nil
                    if wasReady { self.onUnavailable?(reason) }
                }
                peer.start()
            }
            listener.start(queue: self.queue)
        }
    }
    func startClient(offer: CursorOffer, video: NWConnection, receive: @escaping (Data) -> Void) throws {
        guard case let .hostPort(host, _) = video.currentPath?.remoteEndpoint ?? video.endpoint, let port = NWEndpoint.Port(rawValue: offer.port) else { throw AireError("No se pudo resolver el canal de cursor.") }
        let parameters = try networkParameters(key: offer.key); parameters.serviceClass = .interactiveVoice
        // Keep the auxiliary connection on the same interface as video (AWDL or LAN).
        if let interface = video.currentPath?.availableInterfaces.first { parameters.requiredInterface = interface }
        // Catalina can reject a reused scoped link-local address. Resolve the
        // authenticated sender's Bonjour hostname for this new socket instead.
        let controlHost: NWEndpoint.Host
        if case .ipv4(let address) = host { controlHost = .ipv4(IPv4Address(address.rawValue)!) }
        else { controlHost = offer.host.isEmpty ? host : NWEndpoint.Host(offer.host) }
        let rawEndpoint = NWEndpoint.hostPort(host: controlHost, port: port)
        if video.currentPath?.availableInterfaces.contains(where: { $0.name == "awdl0" }) != true {
            parameters.includePeerToPeer = false
        }
        if case .ipv4 = host, let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4; parameters.defaultProtocolStack.internetProtocol = ip
        }
        queue.async {
            self.stopOnQueue(); let token = self.generation; self.received = receive
            let connection = NWConnection(to: rawEndpoint, using: parameters)
            self.connectClient(connection, token: token)
        }
    }
    private func connectClient(_ connection: NWConnection, token: UUID) {
            let peer = Peer(connection, queue: self.queue); self.peer = peer
            peer.onReady = { peer.send(.hello, Wire.hello(role: "cursor-receiver")) }
            peer.onPacket = { [weak self, weak peer] kind, data in
                guard let self = self, self.generation == token, let peer = peer else { return }
                do {
                    if kind == .hello {
                        guard !self.authenticated else { throw AireError("Saludo de cursor duplicado.") }
                        _ = try Wire.checkHello(data, expected: "cursor-sender"); self.authenticated = true; self.setReady(true); self.onReady?()
                    } else if kind == .cursor, self.authenticated {
                        guard data.count == PointerMessage.encodedSize + 2, data[0] <= 1, data[1] <= 1 else { throw AireError("Cursor inválido.") }
                        let position = try PointerMessage(Data(data.dropFirst(2)))
                        guard position.action == .move else { throw AireError("Cursor inválido.") }
                        self.received?(data)
                    } else if kind == .desktopControl, self.authenticated { self.onInput?(kind, data) }
                    else { throw AireError("Mensaje de cursor inesperado.") }
                } catch { peer.end("\(error)") }
            }
            peer.onEnd = { [weak self] reason in guard let self = self, self.generation == token else { return }; self.peer = nil; self.authenticated = false; self.setReady(false); self.onUnavailable?(reason) }
            peer.start()
    }
    // A session pins its input transport at the first input. Never replay a click
    // on another socket after a failure: the owner releases input and reconnects.
    func sendInput(_ kind: Wire.Kind, _ data: Data) {
        queue.async {
            guard self.authenticated, let peer = self.peer else { self.onUnavailable?("El canal de control se interrumpió."); return }
            peer.send(kind, data)
        }
    }
    func sendPosition(_ data: Data) {
        queue.async { self.pending = data; self.flush() }
    }
    func sample(_ producer: @escaping () -> Data?, fallback: @escaping (Data, @escaping () -> Void) -> Void) {
        queue.async {
            self.timer?.cancel(); self.previous = nil; self.fallbackSend = fallback
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            var interval = 8
            #if DIAGNOSTIC_SCENE
            if CommandLine.arguments.contains("cursor-four") { interval = 4 }
            if CommandLine.arguments.contains("cursor-sixteen") { interval = 16 }
            #endif
            timer.schedule(deadline: .now(), repeating: .milliseconds(interval), leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in
                guard let self = self, let body = producer(), body != self.previous else { return }
                self.previous = body
                self.pending = body; self.flush()
            }
            self.timer = timer; timer.resume()
        }
    }
    // At most one send is being processed and one most-recent position is retained.
    private func flush() {
        guard !sending, let data = pending else { return }
        pending = nil; sending = true; let token = generation
        let complete: () -> Void = { [weak self] in
            self?.queue.async { [weak self] in
                guard let self = self, self.generation == token else { return }
                self.sending = false; self.flush()
            }
        }
        if authenticated, let peer = peer { peer.send(.cursor, data, completion: complete) }
        else if let fallback = fallbackSend { fallback(data, complete) }
        else { sending = false }
    }
    func stop() { queue.async { self.stopOnQueue() } }
    private func stopOnQueue() {
        generation = UUID(); timer?.cancel(); timer = nil
        listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil; listener?.cancel(); listener = nil
        let old = peer; peer = nil; old?.onEnd = nil; old?.end()
        pending = nil; previous = nil; sending = false; authenticated = false; setReady(false); received = nil; fallbackSend = nil
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
