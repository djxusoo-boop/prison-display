import Foundation
#if !LEGACY
import Network
#endif
import Security
#if !LEGACY
import CryptoKit
#endif

struct AireError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
enum Wire {
    static let revision: UInt16 = 10
    static let maxPacket = 4 * 1024 * 1024
    static let pointerSize = 42
    static let service = "_airedisplay._tcp"
    enum Kind: UInt8 { case hello = 1, video = 2, ack = 3, ping = 4, pong = 5, failure = 6, pointer = 7, cursor = 8, cursorOffer = 9, keyboard = 10, cursorMode = 11, desktopControl = 12, desktopPointer = 13, desktopKeyboard = 14, presented = 15, brightnessCommand = 16, brightnessResult = 17, fullscreenCommand = 18 }
    static func validateFullscreenCommand(_ data: Data) throws {
        guard data.isEmpty else { throw AireError("Orden de pantalla completa inválida.") }
    }
    static func packet(_ kind: Kind, _ body: Data = Data()) -> Data {
        var d = Data(); d.u32(UInt32(body.count + 1)); d.append(kind.rawValue); d.append(body); return d
    }
    static func hello(role: String, name: String = Host.current().localizedName ?? "Este Mac") -> Data {
        let label = normalizedPeerName(name) ?? "Este Mac"
        var d = Data(); d.u16(revision)
        d.append(Data("\(role)|\(AppVersion.current)|\(Data(label.utf8).base64EncodedString())".utf8)); return d
    }
    static func normalizedPeerName(_ name: String) -> String? {
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label.count <= 64,
              !label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return label
    }
    static func peerName(_ data: Data) throws -> String {
        guard data.count <= 512, let text = String(data: data.dropFirst(2), encoding: .utf8) else { throw AireError("Identidad del equipo inválida.") }
        let fields = text.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 3, let decoded = Data(base64Encoded: String(fields[2])),
              let name = String(data: decoded, encoding: .utf8), let label = normalizedPeerName(name) else { throw AireError("Identidad del equipo inválida.") }
        return label
    }
    static func checkHello(_ data: Data, expected: String) throws -> String {
        var r = Reader(data); guard try r.u16() == revision else { throw AireError("Versiones de protocolo incompatibles. Actualiza ambas apps.") }
        guard data.count <= 512, let s = String(data: try r.rest(), encoding: .utf8) else { throw AireError("Saludo inválido.") }
        let fields = s.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 3, fields[0] == expected else { throw AireError("La otra app tiene un rol incorrecto.") }
        let version = String(fields[1])
        guard version == AppVersion.current else { throw AireError("Versiones distintas (remota \(version), local \(AppVersion.current)). Actualiza ambas apps.") }
        _ = try peerName(data)
        return version
    }
}
extension Data {
    mutating func u16(_ v: UInt16) { append(UInt8(v >> 8)); append(UInt8(v & 255)) }
    mutating func u32(_ v: UInt32) { for s in stride(from: 24, through: 0, by: -8) { append(UInt8((v >> s) & 255)) } }
    mutating func u64(_ v: UInt64) { for s in stride(from: 56, through: 0, by: -8) { append(UInt8((v >> s) & 255)) } }
}
struct Reader {
    private let data: Data; private var offset = 0
    init(_ data: Data) { self.data = Data(data) }
    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, count <= data.count - offset else { throw AireError("Paquete incompleto.") }
        defer { offset += count }; return data.subdata(in: offset..<(offset + count))
    }
    mutating func u16() throws -> UInt16 { try bytes(2).reduce(UInt16(0)) { ($0 << 8) | UInt16($1) } }
    mutating func u32() throws -> UInt32 { try bytes(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } }
    mutating func u64() throws -> UInt64 { try bytes(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } }
    mutating func rest() throws -> Data { try bytes(data.count - offset) }
}
struct PacketParser {
    private var buffer = Data()
    mutating func feed(_ data: Data) throws -> [(Wire.Kind, Data)] {
        buffer.append(data); var packets: [(Wire.Kind, Data)] = []
        while buffer.count >= 4 {
            var r = Reader(buffer.prefix(4)); let length = Int(try r.u32())
            guard length >= 1, length <= Wire.maxPacket else { throw AireError("Tamaño de paquete inválido.") }
            guard buffer.count >= length + 4 else { break }
            guard let kind = Wire.Kind(rawValue: buffer[buffer.startIndex + 4]) else { throw AireError("Tipo de paquete desconocido.") }
            packets.append((kind, Data(buffer.dropFirst(5).prefix(length - 1))))
            buffer = Data(buffer.dropFirst(length + 4))
        }
        return packets
    }
}
func monotonicNS() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
func newPairingKey() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 16)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AireError("No se pudo crear la clave.") }
    return bytes.map { String(format: "%02X", $0) }.joined()
}
func normalizedKey(_ s: String) throws -> String {
    let key = s.filter { !$0.isWhitespace && $0 != "-" }.uppercased()
    guard key.count == 32, key.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }) else { throw AireError("Copia la clave de 32 caracteres del MacBook.") }
    return key
}
func networkParameters(key: String) throws -> NWParameters {
    let key = try normalizedKey(key)
    let secret = Data(SHA256.hash(data: Data(("AireDisplay:" + key).utf8)))
    #if LEGACY
    return NWParameters(secret: secret)
    #else
    let identity = Data("AireDisplay-v1".utf8)
    let tls = NWProtocolTLS.Options()
    secret.withUnsafeBytes { a in identity.withUnsafeBytes { b in
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, DispatchData(bytes: a) as __DispatchData, DispatchData(bytes: b) as __DispatchData)
    }}
    sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
    sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
    sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions, tls_ciphersuite_t(rawValue: 0x00A8)!)
    let tcp = NWProtocolTCP.Options(); tcp.noDelay = true; tcp.connectionTimeout = 10
    #if DIAGNOSTIC_SCENE || REAL_ROUTE_DIAGNOSTIC
    if CommandLine.arguments.contains("ack-fast") { tcp.disableAckStretching = true }
    #endif
    let p = NWParameters(tls: tls, tcp: tcp)
    // Shared-network Bonjour keeps automatic discovery without asking the Wi-Fi
    // radio to maintain a second peer-to-peer network during the stream.
    p.includePeerToPeer = false
    #if DIAGNOSTIC_SCENE || REAL_ROUTE_DIAGNOSTIC
    if CommandLine.arguments.contains("peer-wifi") { p.includePeerToPeer = true }
    #endif
    p.serviceClass = .interactiveVideo
    return p
    #endif
}
// Keep packet boundaries intact, but let cursor positions pass queued video.
// Control messages (handshakes, clicks, acknowledgements) remain ordering barriers.
final class PriorityPacketQueue {
    struct Item {
        let kind: Wire.Kind
        let resolve: () -> Data
        var body: Data { resolve() }
        let completion: (() -> Void)?
    }
    private var items: [Item] = []
    private func moveScope(_ kind: Wire.Kind, _ body: Data) -> Data? {
        let offset: Int
        switch kind { case .pointer: offset = 0; case .desktopPointer: offset = 8; default: return nil }
        guard body.count == Wire.pointerSize + offset, body[offset] == 0 else { return nil }
        return Data(body.prefix(offset))
    }
    func append(_ kind: Wire.Kind, _ body: Data, completion: (() -> Void)?) {
        let item = Item(kind: kind, resolve: { body }, completion: completion)
        // Retain only the newest unsent movement within the same input session.
        // Clicks, keys, scrolls, lease changes and completion callbacks are barriers.
        if completion == nil, let previous = items.last, previous.completion == nil,
           previous.kind == kind, let scope = moveScope(kind, body), moveScope(previous.kind, previous.body) == scope {
            items[items.count-1] = item
        } else { items.append(item) }
    }
    func appendCursor(_ sample: @escaping () -> Data, completion: (() -> Void)?) {
        items.append(Item(kind: .cursor, resolve: sample, completion: completion))
    }
    func take() -> Item? {
        guard !items.isEmpty else { return nil }
        var selected = 0
        if items[0].kind == .video {
            for index in items.indices {
                if items[index].kind == .cursor { selected = index; break }
                if items[index].kind != .video { break }
            }
        }
        return items.remove(at: selected)
    }
    func clear() { items.removeAll() }
}

// A receive callback can contain several complete frames followed by a cursor.
// Deliver positions before decoding that run of video, without crossing controls.
func cursorFirst(_ packets: [(Wire.Kind, Data)]) -> [(Wire.Kind, Data)] {
    var result: [(Wire.Kind, Data)] = []
    var images: [(Wire.Kind, Data)] = []
    for packet in packets {
        if packet.0 == .video { images.append(packet) }
        else if packet.0 == .cursor { result.append(packet) }
        else { result.append(contentsOf: images); images.removeAll(keepingCapacity: true); result.append(packet) }
    }
    result.append(contentsOf: images)
    return result
}

// A TCP receive after a radio stall can contain a run of obsolete movements.
// Apply only its newest position, preserving every click/key/lease barrier.
func recentMovements(_ packets: [(Wire.Kind, Data)]) -> [(Wire.Kind, Data)] {
    func scope(_ packet: (Wire.Kind, Data)) -> Data? {
        let offset: Int
        switch packet.0 { case .pointer: offset = 0; case .desktopPointer: offset = 8; case .cursor: offset = 2; default: return nil }
        guard packet.1.count == Wire.pointerSize + offset, packet.1[offset] == 0 else { return nil }
        return Data(packet.1.prefix(packet.0 == .desktopPointer ? 8 : 0))
    }
    var result: [(Wire.Kind, Data)] = []
    for packet in packets {
        if let last = result.last, last.0 == packet.0, let token = scope(packet), scope(last) == token {
            result[result.count-1] = packet
        } else { result.append(packet) }
    }
    return result
}

// Coalesce across network callbacks too: a busy capture queue must not replay
// every old mouse position after it becomes available. Keys, clicks and leases
// stay in order. A bounded overflow disconnects rather than losing a release.
final class OrderedInputDelivery {
    private let lock = NSLock()
    private let queue: DispatchQueue
    private let receive: (Wire.Kind, Data) -> Void
    private let overflow: () -> Void
    private let limit: Int
    private var pending: [(Wire.Kind, Data)] = []
    private var scheduled = false
    private var cancelled = false
    private var generation: UInt64 = 0
    var pendingCount: Int { lock.lock(); defer { lock.unlock() }; return pending.count }
    init(queue: DispatchQueue, limit: Int = 4096, receive: @escaping (Wire.Kind, Data) -> Void, overflow: @escaping () -> Void) {
        self.queue = queue; self.limit = max(1, limit); self.receive = receive; self.overflow = overflow
    }
    func submit(_ kind: Wire.Kind, _ body: Data) {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        let packet = (kind, body)
        if let last = pending.last, recentMovements([last, packet]).count == 1 { pending[pending.count-1] = packet }
        else { pending.append(packet) }
        if pending.count > limit {
            cancelled = true; generation &+= 1; pending.removeAll(); scheduled = false
            lock.unlock(); queue.async { [weak self] in self?.overflow() }; return
        }
        let token = generation, needsSchedule = !scheduled
        scheduled = true; lock.unlock()
        if needsSchedule { schedule(token) }
    }
    private func schedule(_ token: UInt64) { queue.async { [weak self] in self?.drain(token) } }
    private func drain(_ token: UInt64) {
        lock.lock()
        guard !cancelled, generation == token else { lock.unlock(); return }
        let batch = Array(pending.prefix(64)); pending.removeFirst(batch.count)
        lock.unlock()
        for (kind, body) in batch {
            lock.lock(); let valid = !cancelled && generation == token; lock.unlock()
            if !valid { return }
            receive(kind, body)
        }
        lock.lock()
        guard !cancelled, generation == token else { lock.unlock(); return }
        let more = !pending.isEmpty
        if !more { scheduled = false }
        lock.unlock()
        if more { schedule(token) }
    }
    func cancel() {
        lock.lock(); cancelled = true; generation &+= 1; pending.removeAll(); scheduled = false; lock.unlock()
    }
}

final class Peer {
    let connection: NWConnection
    let queue: DispatchQueue
    var onReady: (() -> Void)?
    var onPacket: ((Wire.Kind, Data) -> Void)?
    var onEnd: ((String) -> Void)?
    private var parser = PacketParser()
    private let outgoing = PriorityPacketQueue()
    private var sending = false
    private var ended = false
    private var ready = false
    private var lastReceive = monotonicNS()
    private var watchdog: DispatchSourceTimer?
    private let timeoutNS: UInt64
    init(_ c: NWConnection, queue: DispatchQueue, timeoutSeconds: UInt64 = 12) { connection = c; self.queue = queue; timeoutNS = timeoutSeconds * 1_000_000_000 }
    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self, !self.ended else { return }
            switch state {
            case .ready: self.ready = true; self.lastReceive = monotonicNS(); self.onReady?(); self.receive()
            case .failed(let e): self.end("No se pudo conectar. Comprueba la clave, la red y el cortafuegos. (\(e))")
            case .waiting(let e): self.end("Conexión en espera: \(e)")
            case .cancelled: self.end("Desconectado.")
            default: break
            }
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if monotonicNS() - self.lastReceive > self.timeoutNS { self.end("La conexión dejó de responder.") }
            else if self.ready { self.send(.ping) }
        }
        watchdog = timer; timer.resume(); connection.start(queue: queue)
    }
    func send(_ kind: Wire.Kind, _ data: Data = Data(), completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self, !self.ended, data.count + 1 <= Wire.maxPacket else { return }
            self.outgoing.append(kind, data, completion: completion)
            self.flushSend()
        }
    }
    // Resolve the cursor at the actual send boundary, not when a busy socket queues it.
    func sendCursor(_ sample: @escaping () -> Data, completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self, !self.ended else { return }
            self.outgoing.appendCursor(sample, completion: completion)
            self.flushSend()
        }
    }
    private func flushSend() {
        guard !ended, !sending, let packet = outgoing.take() else { return }
        let body = packet.body
        guard body.count + 1 <= Wire.maxPacket else { end("Tamaño de paquete inválido."); return }
        sending = true
        connection.send(content: Wire.packet(packet.kind, body), completion: .contentProcessed { [weak self] error in
            guard let self = self, !self.ended else { return }
            self.sending = false
            if let error = error { self.end("Error de envío: \(error)") }
            else { packet.completion?(); self.flushSend() }
        })
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self = self, !self.ended else { return }
            do {
                if let data = data, !data.isEmpty {
                    self.lastReceive = monotonicNS()
                    for (kind, body) in cursorFirst(recentMovements(try self.parser.feed(data))) {
                        guard !self.ended else { break }
                        if kind == .ping { self.send(.pong) }
                        else if kind != .pong { self.onPacket?(kind, body) }
                    }
                }
                if let error = error { self.end("Error de recepción: \(error)") }
                else if done { self.end("El otro Mac se desconectó.") }
                else { self.receive() }
            } catch { self.end("\(error)") }
        }
    }
    func end(_ reason: String = "Desconectado.") {
        guard !ended else { return }; ended = true
        outgoing.clear(); sending = false
        watchdog?.cancel(); watchdog = nil
        connection.stateUpdateHandler = nil; connection.cancel(); onEnd?(reason)
        onReady = nil; onPacket = nil; onEnd = nil
    }
}

// A small bounded window overlaps transport and presentation without an unbounded queue.
struct VideoWindow {
    static let capacity = 3
    private var limit: Int
    init(limit: Int = Self.capacity) { self.limit = min(Self.capacity, max(1, limit)) }
    private var timestamps: [UInt64: (captured: UInt64, handed: UInt64)] = [:]
    var hasRoom: Bool { timestamps.count < limit }
    var availableSlots: Int { max(0, limit-timestamps.count) }
    var isEmpty: Bool { timestamps.isEmpty }
    // Changing the bound must never forget frames already sent.
    mutating func setLimit(_ value: Int) { limit = min(Self.capacity, max(1, value)) }
    mutating func sent(sequence: UInt64, timestamp: UInt64, handedAt: UInt64 = monotonicNS()) throws {
        guard hasRoom, timestamps[sequence] == nil else { throw AireError("Límite de imágenes en tránsito excedido.") }
        timestamps[sequence] = (timestamp, handedAt)
    }
    @discardableResult
    mutating func acknowledge(sequence: UInt64, timestamp: UInt64, now: UInt64 = monotonicNS()) throws -> UInt64 {
        guard let stamp = timestamps[sequence], stamp.captured == timestamp, now >= stamp.handed else { throw AireError("Confirmación de vídeo inválida.") }
        timestamps.removeValue(forKey: sequence)
        // Quality follows transport/decode congestion, not time already spent
        // inside the local encoder. Otherwise a slow Intel codec permanently
        // reduced image quality even on a healthy LAN.
        return now-stamp.handed
    }
    mutating func reset() { timestamps.removeAll() }
}

func discoveryParameters() -> NWParameters {
    let parameters = NWParameters.tcp
    parameters.includePeerToPeer = false
    #if DIAGNOSTIC_SCENE || REAL_ROUTE_DIAGNOSTIC
    if CommandLine.arguments.contains("peer-wifi") { parameters.includePeerToPeer = true }
    #endif
    return parameters
}

// Catalina's reused link-local IPv6 routes can stall or fail for an auxiliary
// socket. Prefer IPv4 on a resolved LAN; the engine retries IPv6 if unavailable.
@discardableResult
func configureStreamRoute(_ parameters: NWParameters, endpoint: NWEndpoint, preferIPv4: Bool = true) -> Bool {
    if case let .hostPort(host, _) = endpoint, case let .name(name, _) = host,
       name.lowercased().hasSuffix(".local") {
        parameters.includePeerToPeer = false
        if preferIPv4, let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4; parameters.defaultProtocolStack.internetProtocol = ip; return true
        }
        return false
    }
    guard case let .service(_, _, _, interface) = endpoint, let interface = interface else { return false }
    parameters.requiredInterface = interface
    guard interface.name != "awdl0", interface.type == .wifi || interface.type == .wiredEthernet else { return false }
    parameters.includePeerToPeer = false
    if preferIPv4, let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
        ip.version = .v4; parameters.defaultProtocolStack.internetProtocol = ip; return true
    }
    return false
}

func prefersSharedLAN(_ endpoint: NWEndpoint) -> Bool {
    guard case let .service(_, _, _, interface) = endpoint, let interface = interface else { return false }
    return interface.name != "awdl0" && (interface.type == .wifi || interface.type == .wiredEthernet)
}

// Resolve Bonjour on the shared LAN. Production discovery does not enable AWDL.
// Browse only during resolution, never for the lifetime of a connected stream.
final class VideoRouteResolver {
    private var browser: NWBrowser?
    private var generation = UUID()
    func cancel() { generation = UUID(); browser?.cancel(); browser = nil }
    func resolve(_ endpoint: NWEndpoint, queue: DispatchQueue, completion: @escaping (NWEndpoint) -> Void) {
        cancel()
        #if LEGACY
        completion(endpoint); return
        #else
        guard case let .service(name, type, domain, _) = endpoint else { completion(endpoint); return }
        let token = generation
        let browse = NWBrowser(for: .bonjour(type: type, domain: domain), using: discoveryParameters())
        browser = browse
        let finish: (NWEndpoint) -> Void = { [weak self] chosen in
            guard let self = self, self.generation == token else { return }
            self.cancel(); completion(chosen)
        }
        browse.browseResultsChangedHandler = { results, _ in
            for result in results {
                guard case let .service(found, _, _, _) = result.endpoint, found == name,
                      let local = result.interfaces.first(where: { $0.type == .wiredEthernet || ($0.type == .wifi && $0.name != "awdl0") }) else { continue }
                finish(.service(name: name, type: type, domain: domain, interface: local)); return
            }
        }
        browse.stateUpdateHandler = { state in if case .failed = state { finish(endpoint) } }
        browse.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 2) { finish(endpoint) }
        #endif
    }
}

// Strict, small messages. No display capture or input permission is needed.
struct BrightnessCommand: Codable {
    let id: UUID
    let percent: Int
    init(percent: Int, id: UUID = UUID()) throws {
        guard (5...100).contains(percent) else { throw AireError("Brillo fuera de rango.") }
        self.id = id; self.percent = percent
    }
    init(data: Data) throws {
        guard data.count <= 1024 else { throw AireError("Ajuste de brillo demasiado grande.") }
        let command = try JSONDecoder().decode(Self.self, from: data)
        try self.init(percent: command.percent, id: command.id)
    }
    var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }
}
struct BrightnessResult: Codable {
    let id: UUID
    let node: UUID
    let name: String
    let percent: Int?
    init(id: UUID, node: UUID, name: String, percent: Int?) {
        self.id = id; self.node = node; self.name = String(name.filter { !$0.isNewline && !$0.isASCIIControl }.prefix(60)); self.percent = percent
    }
    init(data: Data) throws {
        guard data.count <= 1024 else { throw AireError("Confirmación de brillo demasiado grande.") }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.name.count <= 60, result.percent.map({ (0...100).contains($0) }) ?? true else { throw AireError("Confirmación de brillo inválida.") }
        self.init(id: result.id, node: result.node, name: result.name, percent: result.percent)
    }
    var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }
}
private extension Character {
    var isASCIIControl: Bool { unicodeScalars.contains { $0.value < 32 || $0.value == 127 } }
}
