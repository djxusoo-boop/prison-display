#if UNIFIED && !LEGACY
import AppKit
import Network
import Security
import CryptoKit

extension Wire {
    // The PC app has its own version. Another protocol revision is accepted
    // only to update it (sameRevision false).
    static func checkPCHello(_ data: Data) throws -> (name: String, version: String, sameRevision: Bool) {
        var r = Reader(data)
        let remoteRevision = try r.u16()
        guard data.count <= 512, let text = String(data: try r.rest(), encoding: .utf8) else { throw AireError("Saludo del PC inválido.") }
        let fields = text.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 3, fields[0] == "pc", let version = normalizedVersion(String(fields[1])) else { throw AireError("Ese equipo no es PRISON DISPLAY para Windows.") }
        return (try peerName(data), version, remoteRevision == revision)
    }
}

// Where the PC is and its key. The key lives in the Keychain, never in preferences.
struct PCLinkSettings: Equatable {
    var host = ""
    var key = ""
    var edge = DesktopEdge.right.rawValue
    var enabled = false
    private static let service = "local.prisondisplay.pc.v1"
    static func load(defaults: UserDefaults = .standard, readKey: Bool = true) -> PCLinkSettings {
        var s = PCLinkSettings()
        s.host = defaults.string(forKey: "PrisonDisplay.pc.host") ?? ""
        let edge = defaults.integer(forKey: "PrisonDisplay.pc.edge")
        s.edge = DesktopEdge(rawValue: edge) != nil ? edge : DesktopEdge.right.rawValue
        s.enabled = defaults.bool(forKey: "PrisonDisplay.pc.enabled")
        if readKey {
            var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "default"]
            query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data { s.key = String(data: data, encoding: .utf8) ?? "" }
        }
        return s
    }
    func save(defaults: UserDefaults = .standard) {
        defaults.set(host, forKey: "PrisonDisplay.pc.host"); defaults.set(edge, forKey: "PrisonDisplay.pc.edge"); defaults.set(enabled, forKey: "PrisonDisplay.pc.enabled")
        guard !key.isEmpty else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: "default"]
        let data = Data(key.utf8)
        if SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }
    // "10.0.0.13", "torre.local" or "10.0.0.13:37941".
    static func endpoint(_ text: String) throws -> (String, UInt16) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 253, !value.contains(" ") else { throw AireError("Escribe la dirección que muestra el PC, por ejemplo 10.0.0.13.") }
        if let colon = value.lastIndex(of: ":"), !value.contains("::") {
            let host = String(value[..<colon]), port = UInt16(value[value.index(after: colon)...])
            guard !host.isEmpty, let p = port, p > 0 else { throw AireError("Puerto inválido.") }
            return (host, p)
        }
        return (value, pcInputPort)
    }
}
let pcInputPort: UInt16 = 37941

// A PC announcing itself on the local network.
struct FoundPC: Equatable {
    let name: String, version: String, host: String, inputPort: UInt16, pairingPort: UInt16
    // "PRISON-PC/1|name|version|input port|pairing port"
    init?(announcement: String, from host: String) {
        let f = announcement.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count == 5, f[0] == "PRISON-PC/1", let name = Wire.normalizedPeerName(f[1]), Wire.normalizedVersion(f[2]) != nil,
              let input = UInt16(f[3]), let pair = UInt16(f[4]), input > 0, pair > 0, !host.isEmpty else { return nil }
        self.name = name; version = f[2]; self.host = host; inputPort = input; pairingPort = pair
    }
}
enum PCDiscovery {
    // Listens for PC broadcasts for a few seconds (background thread).
    static func scan(seconds: Double = 4, port: UInt16 = 37930, completion: @escaping ([FoundPC]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var found: [FoundPC] = []
            let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard fd >= 0 else { DispatchQueue.main.async { completion([]) }; return }
            defer { close(fd) }
            var yes: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
            var timeout = timeval(tv_sec: 0, tv_usec: 250_000)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var address = sockaddr_in(); address.sin_family = sa_family_t(AF_INET); address.sin_port = port.bigEndian; address.sin_addr.s_addr = INADDR_ANY
            let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
            guard bound == 0 else { DispatchQueue.main.async { completion([]) }; return }
            let deadline = Date().addingTimeInterval(seconds)
            var buffer = [UInt8](repeating: 0, count: 512)
            while Date() < deadline {
                var source = sockaddr_in(); var length = socklen_t(MemoryLayout<sockaddr_in>.size)
                let count = withUnsafeMutablePointer(to: &source) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buffer, buffer.count, 0, $0, &length) } }
                guard count > 0, let text = String(bytes: buffer[0..<count], encoding: .utf8) else { continue }
                var ip = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN)); var addr = source.sin_addr
                inet_ntop(AF_INET, &addr, &ip, socklen_t(INET_ADDRSTRLEN))
                if let pc = FoundPC(announcement: text, from: String(cString: ip)), !found.contains(where: { $0.host == pc.host }) { found.append(pc) }
            }
            DispatchQueue.main.async { completion(found) }
        }
    }
}

// Pair with a PC without typing its key: P-256 agreement, the same 6-digit
// code on both screens, then the PC key arrives encrypted (AES-GCM).
final class PCPairing {
    private let queue = DispatchQueue(label: "PrisonDisplay.pc-pairing")
    private var peer: Peer?
    func start(host: String, port: UInt16, confirm: @escaping (String, String, @escaping (Bool) -> Void) -> Void,
               completion: @escaping (Result<(key: String, port: UInt16, name: String), Error>) -> Void) {
        queue.async {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { DispatchQueue.main.async { completion(.failure(AireError("Puerto inválido."))) }; return }
            let privateKey = P256.KeyAgreement.PrivateKey()
            let own = privateKey.publicKey.x963Representation
            var key: SymmetricKey?, transcript = Data(), pcName = "PC", accepted = false, done = false
            let p = Peer(NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: discoveryParameters()), queue: self.queue, timeoutSeconds: 120)
            self.peer = p
            func finish(_ result: Result<(key: String, port: UInt16, name: String), Error>) {
                guard !done else { return }; done = true
                p.onEnd = nil; p.end(); self.peer = nil
                DispatchQueue.main.async { completion(result) }
            }
            p.onReady = {
                let name = Wire.normalizedPeerName(Host.current().localizedName ?? "Mac") ?? "Mac"
                p.send(.hello, Data("pc-pair-v1|\(name)|\(own.base64EncodedString())".utf8))
            }
            p.onPacket = { kind, data in
                do {
                    switch kind {
                    case .hello:
                        guard key == nil, data.count <= 1024, let text = String(data: data, encoding: .utf8) else { throw AireError("Respuesta del PC inválida.") }
                        let f = text.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                        guard f.count == 3, f[0] == "pc-pair-v1", let name = Wire.normalizedPeerName(f[1]), let remote = Data(base64Encoded: f[2]) else { throw AireError("Respuesta del PC inválida.") }
                        let pcPublic = try P256.KeyAgreement.PublicKey(x963Representation: remote)
                        transcript = Data("PRISON-PC-pair-v1".utf8) + own + remote
                        let shared = try privateKey.sharedSecretFromKeyAgreement(with: pcPublic)
                        let derived = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("AireDisplay pairing".utf8), sharedInfo: transcript, outputByteCount: 32)
                        key = derived; pcName = name
                        let digest = derived.withUnsafeBytes { SHA256.hash(data: Data($0) + Data("verify".utf8)) }
                        let value = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                        let code = String(format: "%06u", value % 1_000_000)
                        DispatchQueue.main.async {
                            confirm(name, code) { ok in self.queue.async {
                                if ok { accepted = true; p.send(.ack) } else { p.send(.failure, Data("Cancelado en el Mac.".utf8)); finish(.failure(AireError("Emparejamiento cancelado."))) }
                            } }
                        }
                    case .video:
                        guard accepted, let key = key, data.count <= 1024 else { throw AireError("El PC envió la clave sin confirmación.") }
                        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: transcript)
                        let f = (String(data: plain, encoding: .utf8) ?? "").split(separator: "|").map(String.init)
                        guard f.count == 3, let port = UInt16(f[1]), port > 0 else { throw AireError("Datos del PC inválidos.") }
                        finish(.success((try normalizedKey(f[0]), port, pcName)))
                    case .failure:
                        throw AireError(String(data: data.prefix(256), encoding: .utf8) ?? "El PC rechazó el emparejamiento.")
                    default: break
                    }
                } catch { finish(.failure(error)) }
            }
            p.onEnd = { reason in finish(.failure(AireError("Emparejamiento interrumpido: \(reason)"))) }
            p.start()
        }
    }
    func cancel() { queue.async { let p = self.peer; self.peer = nil; p?.end() } }
}

// The Mac's own mouse and keyboard continue onto a Windows PC: cross the chosen
// edge of the outermost display and the PC takes them; come back by the same
// edge or press ⌃⌥Esc. Uses the same lease rules as Mac-to-Mac crossing.
final class WindowsLink {
    static let shared = WindowsLink()
    let bridge = DesktopBridge()
    var onStatus: (String) -> Void = { _ in }
    var onConnected: (String?) -> Void = { _ in }
    var onClipboard: ((Data) -> Void)?
    // Newer Windows build carried by this Mac: (file, version).
    var windowsUpdate: () -> (URL, String)? = { nil }
    var streamUpdate: (URL, String, @escaping (Wire.Kind, Data) -> Void) throws -> Void = { _, _, _ in throw AireError("Sin actualizador.") }
    func sendClipboard(_ data: Data) { queue.async { if self.greeted { self.peer?.send(.clipboard, data) } } }
    private let queue = DispatchQueue(label: "PrisonDisplay.windows-link", qos: .userInteractive)
    private var peer: Peer?
    private var greeted = false
    private var requested: UInt64?
    private var token: UInt64?
    private var target: (host: String, port: UInt16, key: String)?
    private var retry: DispatchWorkItem?
    private var generation = 0
    var displays: () -> [CGRect] = {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { DisplayGeometry.shared.bounds($0) }
    }
    init() {
        bridge.sendControl = { [weak self] message in self?.sendControl(message) }
        bridge.sendPointer = { [weak self] message in self?.sendInput(.desktopPointer, message.serialize()) }
        bridge.sendKeyboard = { [weak self] message in self?.sendInput(.desktopKeyboard, message.serialize()) }
        // Cross from the outer edge of all displays, not from the main one:
        // the Air's extended screens sit between it and the PC.
        bridge.bounds = { [weak self] in (self?.displays() ?? []).reduce(CGRect.null) { $0.union($1) } }
        bridge.warp = { [weak self] point in CGWarpMouseCursorPosition(clampToDisplays(point, self?.displays() ?? [])) }
        bridge.onStatus = { [weak self] text in
            self?.onStatus(text.replacingOccurrences(of: "el otro Mac", with: "el PC").replacingOccurrences(of: "del otro Mac", with: "del PC").replacingOccurrences(of: "otro Mac", with: "PC"))
        }
    }
    var isConnected: Bool { queue.sync { greeted } }
    // startBridge: tests drive the bridge with synthetic events instead of a tap.
    func connect(host: String, port: UInt16, key: String, startBridge: Bool = true) throws {
        let key = try normalizedKey(key)
        _ = try networkParameters(key: key)
        if startBridge, !bridge.isActive { try bridge.start() }
        queue.async { self.target = (host, port, key); self.generation += 1; self.open() }
    }
    func disconnect() {
        bridge.stop()
        queue.async {
            self.target = nil; self.generation += 1; self.retry?.cancel(); self.retry = nil
            self.close(); DispatchQueue.main.async { self.bridge.connected = false; self.onConnected(nil) }
        }
    }
    private func close() {
        let old = peer; peer = nil; greeted = false; requested = nil; token = nil
        old?.onEnd = nil; old?.end()
    }
    private func open() {
        close()
        guard let target = target, let port = NWEndpoint.Port(rawValue: target.port), let parameters = try? networkParameters(key: target.key) else { return }
        parameters.serviceClass = .responsiveData
        let session = generation
        let p = Peer(NWConnection(host: NWEndpoint.Host(target.host), port: port, using: parameters), queue: queue)
        peer = p
        DispatchQueue.main.async { self.onStatus("Conectando con el PC en \(target.host)…") }
        p.onReady = { p.send(.hello, Wire.hello(role: "pc-controller")) }
        p.onPacket = { [weak self, weak p] kind, data in
            guard let self = self, let p = p, self.peer === p else { return }
            do {
                if !self.greeted {
                    guard kind == .hello else { throw AireError("El PC no respondió como PRISON DISPLAY.") }
                    let hello = try Wire.checkPCHello(data), name = hello.name
                    if let (file, version) = self.windowsUpdate(), AppVersion.compare(version, hello.version) > 0 {
                        DispatchQueue.main.async { self.onStatus("El PC tiene PRISON DISPLAY \(hello.version). Enviándole la \(version); se reiniciará solo…") }
                        let stream = self.streamUpdate
                        DispatchQueue.global(qos: .userInitiated).async { [weak p] in
                            do { try stream(file, version) { kind, data in p?.send(kind, data) } }
                            catch { DispatchQueue.main.async { self.onStatus("No se pudo actualizar el PC: \(error)") } }
                        }
                        return
                    }
                    guard hello.sameRevision else { throw AireError("El PC tiene otra versión de PRISON DISPLAY y este Mac no lleva su actualización.") }
                    self.greeted = true
                    DispatchQueue.main.async {
                        self.bridge.connected = true; self.onConnected(name)
                        self.onStatus("Conectado con \(name). Lleva el ratón al borde elegido para usar el PC. ⌃⌥Esc vuelve al Mac.")
                    }
                } else if kind == .desktopControl {
                    let message = try DesktopControlMessage(data)
                    if message.action == .accepted, self.requested == message.token { self.token = message.token }
                    if message.action == .rejected, self.requested == message.token { self.token = nil; self.requested = nil }
                    DispatchQueue.main.async { self.bridge.reply(message) }
                } else if kind == .clipboard {
                    _ = try ClipboardPayload(data); self.onClipboard?(data)
                } else if kind == .failure {
                    throw AireError("El PC: " + (String(data: data.prefix(512), encoding: .utf8) ?? "error"))
                }
            } catch { p.end("\(error)") }
        }
        p.onEnd = { [weak self, weak p] reason in
            guard let self = self, let p = p, self.peer === p else { return }
            self.peer = nil; self.greeted = false; self.requested = nil; self.token = nil
            DispatchQueue.main.async {
                self.bridge.connected = false; self.onConnected(nil)
                self.onStatus(reason.contains("clave") || reason.contains("TLS") || reason.contains("-9") ? "No se pudo conectar con el PC. Comprueba la dirección, la clave y que PRISON DISPLAY esté abierto en Windows." : "PC desconectado: \(reason) Reintentando…")
            }
            guard self.target != nil, self.generation == session else { return }
            let work = DispatchWorkItem { [weak self] in guard let self = self, self.generation == session else { return }; self.open() }
            self.retry = work; self.queue.asyncAfter(deadline: .now() + 3, execute: work)
        }
        p.start()
    }
    private func sendControl(_ message: DesktopControlMessage) {
        queue.async {
            guard self.greeted, let peer = self.peer else { return }
            if message.action == .begin { self.requested = message.token }
            peer.send(.desktopControl, message.serialize())
            if message.action == .end, self.requested == message.token { self.requested = nil; self.token = nil }
        }
    }
    private func sendInput(_ kind: Wire.Kind, _ body: Data) {
        queue.async {
            guard self.greeted, let token = self.token, let peer = self.peer else { return }
            var tagged = Data(); tagged.u64(token); tagged.append(body)
            peer.send(kind, tagged)
        }
    }
}
#endif
