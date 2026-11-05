import Foundation
#if !LEGACY
import Network
#endif
#if !LEGACY
import CryptoKit
#endif
import SystemConfiguration
import Security

func localConnectionHostname() -> String {
    if let name = SCDynamicStoreCopyLocalHostName(nil) as String?, !name.isEmpty { return name + ".local" }
    return Host.current().name ?? "Mac.local"
}

struct ConnectionLink {
    let host: String
    let port: UInt16
    let key: String
    let serviceName: String?
    var hostEndpoint: NWEndpoint { .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!) }
    var endpoint: NWEndpoint {
        if let serviceName = serviceName { return .service(name: serviceName, type: Wire.service, domain: "local.", interface: nil) }
        return hostEndpoint
    }
    var url: URL {
        var c = URLComponents(); c.scheme = "airedisplay"; c.host = "connect"
        c.queryItems = [URLQueryItem(name: "host", value: host), URLQueryItem(name: "port", value: String(port)), URLQueryItem(name: "key", value: key), URLQueryItem(name: "version", value: AppVersion.current)]
        if let serviceName = serviceName { c.queryItems?.append(URLQueryItem(name: "service", value: serviceName)) }
        return c.url!
    }
    init(host: String, port: UInt16, key: String, serviceName: String? = nil) throws {
        guard !host.isEmpty, host.count <= 253, !host.contains(where: { $0.isWhitespace }), port > 0 else { throw AireError("Dirección de conexión inválida.") }
        if let name = serviceName { guard !name.isEmpty, name.utf8.count <= 63, !name.contains(where: { $0.isNewline }) else { throw AireError("Servicio de conexión inválido.") } }
        self.serviceName = serviceName
        self.host = host; self.port = port; self.key = try normalizedKey(key)
    }
    init(_ url: URL) throws {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme?.lowercased() == "airedisplay", c.host == "connect", c.path.isEmpty, c.fragment == nil, c.user == nil, c.password == nil else { throw AireError("Este enlace no es de PRISON DISPLAY.") }
        let items = c.queryItems ?? []
        guard (items.count == 4 || items.count == 5), Set(items.map { $0.name }).count == items.count, Set(items.map { $0.name }).isSubset(of: ["host", "port", "key", "version", "service"]) else { throw AireError("Enlace incompleto o duplicado.") }
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        guard values["version"] == AppVersion.current else { throw AireError("El enlace pertenece a otra versión. Actualiza ambas apps.") }
        guard let host = values["host"], let portString = values["port"], let port = UInt16(portString), let key = values["key"] else { throw AireError("Enlace incompleto.") }
        try self.init(host: host, port: port, key: key, serviceName: values["service"])
    }
}

private struct PairHello: Codable {
    let version: String
    let role: String
    let name: String
    let publicKey: Data
    init(role: String, key: P256.KeyAgreement.PublicKey) {
        version = AppVersion.current; self.role = role
        name = String((Host.current().localizedName ?? "Este Mac").prefix(64))
        publicKey = key.x963Representation
    }
    func validate(role: String) throws {
        guard version == AppVersion.current else { throw AireError("Las dos apps deben tener la misma versión.") }
        guard self.role == role, !name.isEmpty, name.count <= 64, publicKey.count == 65 else { throw AireError("Solicitud de conexión inválida.") }
    }
}
private struct Credentials: Codable { let host: String; let port: UInt16; let key: String; let version: String; let serviceName: String? }
private struct PairSecret {
    let key: SymmetricKey
    let transcript: Data
    let code: String
    init(privateKey: P256.KeyAgreement.PrivateKey, remotePublic: Data, isSender: Bool) throws {
        let remote = try P256.KeyAgreement.PublicKey(x963Representation: remotePublic)
        let ownPublic = privateKey.publicKey.x963Representation
        transcript = Data("AireDisplay-pair-v1:\(AppVersion.current)".utf8) + (isSender ? ownPublic + remotePublic : remotePublic + ownPublic)
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: remote)
        key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("AireDisplay pairing".utf8), sharedInfo: transcript, outputByteCount: 32)
        let digest = key.withUnsafeBytes { SHA256.hash(data: Data($0) + Data("verify".utf8)) }
        let value = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        code = String(format: "%06u", value % 1_000_000)
    }
    func encrypt(_ credentials: Credentials) throws -> Data {
        let data = try JSONEncoder().encode(credentials)
        guard let combined = try AES.GCM.seal(data, using: key, authenticating: transcript).combined else { throw AireError("No se pudo cifrar la conexión.") }
        return combined
    }
    func decrypt(_ data: Data) throws -> Credentials {
        let bytes = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: transcript)
        let c = try JSONDecoder().decode(Credentials.self, from: bytes)
        guard c.port > 0, c.version == AppVersion.current else { throw AireError("Datos de conexión incompatibles.") }
        _ = try ConnectionLink(host: c.host, port: c.port, key: c.key, serviceName: c.serviceName); return c
    }
}

final class PairingServer {
    static let service = "_airepair._tcp"
    let queue: DispatchQueue
    var onConfirm: ((String, String, @escaping (Bool) -> Void) -> Void)?
    var onPeerConnected: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    var onRequest: ((Bool) -> Void)?
    private var listener: NWListener?
    private(set) var isReady = false
    var port: NWEndpoint.Port? { listener?.port }
    private var peer: Peer?
    private var generation = UUID()
    init(queue: DispatchQueue) { self.queue = queue }
    func start(streamPort: UInt16, streamKey: String, serviceName: String? = nil, displayLabel: String? = nil) throws {
        let listener = try NWListener(using: discoveryParameters(), on: .any)
        listener.service = NWListener.Service(name: displayLabel ?? Host.current().localizedName ?? "PRISON DISPLAY", type: Self.service)
        self.listener = listener; let token = UUID(); generation = token
        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self, self.generation == token, self.peer == nil else { connection.cancel(); return }
            let p = Peer(connection, queue: self.queue, timeoutSeconds: 120); self.peer = p
            let privateKey = P256.KeyAgreement.PrivateKey()
            var secret: PairSecret?; var peerName: String?; var localAccepted = false; var remoteAccepted = false; var sent = false
            func sendCredentials() {
                guard localAccepted, remoteAccepted, !sent, let secret = secret, let peerName = peerName, self.generation == token, self.peer === p else { return }
                do {
                    sent = true
                    self.onPeerConnected?(peerName)
                    p.send(.video, try secret.encrypt(Credentials(host: localConnectionHostname(), port: streamPort, key: streamKey, version: AppVersion.current, serviceName: serviceName)))
                }
                catch { p.end("\(error)") }
            }
            p.onReady = { p.send(.hello, (try? JSONEncoder().encode(PairHello(role: "sender", key: privateKey.publicKey))) ?? Data()) }
            p.onPacket = { [weak self, weak p] kind, data in
                guard let self = self, let p = p, self.generation == token, self.peer === p else { return }
                do {
                    if kind == .hello {
                        guard secret == nil, data.count <= 2048 else { throw AireError("Solicitud de conexión duplicada o demasiado grande.") }
                        let hello = try JSONDecoder().decode(PairHello.self, from: data); try hello.validate(role: "receiver")
                        peerName = hello.name
                        secret = try PairSecret(privateKey: privateKey, remotePublic: hello.publicKey, isSender: true)
                        self.onRequest?(true)
                        self.onConfirm?(hello.name, secret!.code) { [weak self, weak p] accepted in
                            self?.queue.async {
                                guard let self = self, let p = p, self.generation == token, self.peer === p else { return }
                                guard accepted else { p.send(.failure, Data("Conexión rechazada en el Mac que envía.".utf8)) { p.end("Conexión rechazada.") }; return }
                                localAccepted = true; sendCredentials()
                            }
                        }
                    } else if kind == .ack {
                        guard secret != nil, !remoteAccepted, data.isEmpty else { throw AireError("Confirmación inválida.") }
                        remoteAccepted = true; sendCredentials()
                    } else if kind == .failure { p.end("Conexión cancelada en el Mac que recibe.") }
                    else { throw AireError("Solicitud de conexión inesperada.") }
                } catch { p.send(.failure, Data("\(error)".utf8)) { p.end("\(error)") } }
            }
            p.onEnd = { [weak self, weak p] reason in
                guard let self = self, let p = p, self.generation == token, self.peer === p else { return }
                self.peer = nil
                if !sent {
                    self.onRequest?(false)
                    self.onStatus?("Solicitud finalizada: \(reason). Disponible para otra conexión.")
                }
            }
            self.queue.asyncAfter(deadline: .now() + 120) { [weak self, weak p] in
                if self?.generation == token, self?.peer === p { p?.end("La solicitud de conexión ha caducado.") }
            }
            p.start()
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self = self, self.generation == token, self.listener === listener else { return }
            if case .ready = state { self.isReady = true }
            if case .failed = state { self.isReady = false; self.onStatus?("No se pudo anunciar este Mac. Puedes copiar el enlace.") }
        }
        listener.start(queue: queue)
    }
    func stop() {
        generation = UUID(); isReady = false; listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil; listener?.cancel(); listener = nil
        let p = peer; peer = nil; p?.onEnd = nil; p?.end()
    }
}

final class PairingClient {
    let queue: DispatchQueue
    var onConfirm: ((String, String, @escaping (Bool) -> Void) -> Void)?
    var onConnected: ((ConnectionLink) -> Void)?
    var onStatus: ((String) -> Void)?
    var onEnded: (() -> Void)?
    private var peer: Peer?
    private var generation = UUID()
    init(queue: DispatchQueue) { self.queue = queue }
    func start(endpoint: NWEndpoint) {
        stop(); let token = UUID(); generation = token
        let p = Peer(NWConnection(to: endpoint, using: discoveryParameters()), queue: queue, timeoutSeconds: 120); peer = p
        let privateKey = P256.KeyAgreement.PrivateKey(); var secret: PairSecret?; var localAccepted = false
        p.onReady = { p.send(.hello, (try? JSONEncoder().encode(PairHello(role: "receiver", key: privateKey.publicKey))) ?? Data()) }
        p.onPacket = { [weak self, weak p] kind, data in
            guard let self = self, let p = p, self.generation == token else { return }
            do {
                if kind == .hello {
                    guard secret == nil, data.count <= 2048 else { throw AireError("Respuesta de conexión inválida.") }
                    let hello = try JSONDecoder().decode(PairHello.self, from: data); try hello.validate(role: "sender")
                    secret = try PairSecret(privateKey: privateKey, remotePublic: hello.publicKey, isSender: false)
                    self.onStatus?("Comprueba el código en los dos Mac y acepta la conexión.")
                    self.onConfirm?(hello.name, secret!.code) { [weak self, weak p] accepted in
                        self?.queue.async {
                            guard let self = self, let p = p, self.generation == token, self.peer === p else { return }
                            if accepted { localAccepted = true; p.send(.ack) }
                            else { p.send(.failure) { p.end("Conexión cancelada.") } }
                        }
                    }
                } else if kind == .video {
                    guard localAccepted, let secret = secret, data.count <= 4096 else { throw AireError("Conexión no verificada.") }
                    let credentials = try secret.decrypt(data)
                    // Keep Bonjour's hostname: Catalina can connect by name but fail
                    // when a resolved link-local IPv6 address is reused for a new socket.
                    let link = try ConnectionLink(host: credentials.host, port: credentials.port, key: credentials.key, serviceName: credentials.serviceName)
                    let connected = self.onConnected
                    self.stop(); connected?(link)
                } else if kind == .failure {
                    guard data.count <= 2048 else { throw AireError("Respuesta de conexión inválida.") }
                    throw AireError(String(data: data, encoding: .utf8) ?? "Conexión rechazada.")
                }
                else { throw AireError("Respuesta inesperada.") }
            } catch { p.end("\(error)") }
        }
        p.onEnd = { [weak self] reason in guard let self = self, self.generation == token else { return }; self.peer = nil; self.onStatus?(reason); self.onEnded?() }
        queue.asyncAfter(deadline: .now() + 120) { [weak self, weak p] in
            if self?.generation == token, self?.peer === p { p?.end("La solicitud de conexión ha caducado.") }
        }
        p.start()
    }
    func stop() { generation = UUID(); let p = peer; peer = nil; p?.onEnd = nil; p?.end() }
}

// Only an explicitly remembered, already authenticated connection is persisted.
// Secrets belong in the user Keychain, never preferences or release archives.
struct TrustedProfile: Codable, Equatable {
    let schema: Int
    let host: String
    let port: UInt16
    let key: String
    let serviceName: String
    init(_ link: ConnectionLink) throws {
        guard let service = link.serviceName else { throw AireError("Esta conexión no puede recordarse. Usa la detección automática.") }
        schema = 1; host = link.host; port = link.port; key = link.key; serviceName = service
    }
    func link() throws -> ConnectionLink {
        guard schema == 1 else { throw AireError("Conexión recordada incompatible.") }
        return try ConnectionLink(host: host, port: port, key: key, serviceName: serviceName)
    }
    func encoded() throws -> Data { _ = try link(); return try JSONEncoder().encode(self) }
    static func decode(_ data: Data) throws -> TrustedProfile {
        guard data.count <= 8192 else { throw AireError("Conexión recordada inválida.") }
        let profile = try JSONDecoder().decode(Self.self, from: data); _ = try profile.link(); return profile
    }
}
final class TrustStore {
    private static let accessLock = NSLock()
    let account: String
    init(account: String) { self.account = account }
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "local.prisondisplay.trust.v1", kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false] }
    func load(allowInteraction: Bool = false) throws -> TrustedProfile? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        // UI callers read on a worker queue with normal authorization. Diagnostics
        // can suppress interaction without replacing the item or its access policy.
        Self.accessLock.lock(); defer { Self.accessLock.unlock() }
        var interaction = DarwinBoolean(false)
        let previous = SecKeychainGetUserInteractionAllowed(&interaction)
        guard previous == errSecSuccess else { throw AireError("No se pudo consultar el Llavero. Conecta normalmente.") }
        let changed = SecKeychainSetUserInteractionAllowed(allowInteraction)
        guard changed == errSecSuccess else { throw AireError("No se pudo preparar la lectura del Llavero (\(changed)).") }
        defer { SecKeychainSetUserInteractionAllowed(interaction.boolValue) }
        var result: CFTypeRef?; let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == errSecUserCanceled {
            throw AireError("El Llavero necesita autorización para recuperar la conexión guardada. Pulsa Recuperar conexión guardada y completa la confirmación de macOS. También puedes conectar normalmente. No se ha borrado la conexión.")
        }
        guard status == errSecSuccess, let data = result as? Data else { throw AireError("No se pudo leer la conexión del Llavero (\(status)). Conecta manualmente.") }
        return try TrustedProfile.decode(data)
    }
    func save(_ profile: TrustedProfile) throws {
        Self.accessLock.lock(); defer { Self.accessLock.unlock() }
        let values: [String: Any] = [kSecValueData as String: try profile.encoded()]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; for (key, value) in values { item[key] = value }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AireError("No se pudo guardar la conexión en el Llavero (\(status)).") }
    }
    func forget() throws {
        Self.accessLock.lock(); defer { Self.accessLock.unlock() }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AireError("No se pudo olvidar la conexión (\(status)).") }
    }
}
