#if UNIFIED && !LEGACY
import AppKit
import Network
import Security

extension Wire {
    // The PC app has its own version; only the protocol revision must match.
    static func checkPCHello(_ data: Data) throws -> String {
        var r = Reader(data)
        guard try r.u16() == revision else { throw AireError("El PC tiene otra versión del protocolo. Actualiza PRISON DISPLAY en Windows.") }
        guard data.count <= 512, let text = String(data: try r.rest(), encoding: .utf8) else { throw AireError("Saludo del PC inválido.") }
        let fields = text.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 3, fields[0] == "pc" else { throw AireError("Ese equipo no es PRISON DISPLAY para Windows.") }
        return try peerName(data)
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

// The Mac's own mouse and keyboard continue onto a Windows PC: cross the chosen
// edge of the outermost display and the PC takes them; come back by the same
// edge or press ⌃⌥Esc. Uses the same lease rules as Mac-to-Mac crossing.
final class WindowsLink {
    static let shared = WindowsLink()
    let bridge = DesktopBridge()
    var onStatus: (String) -> Void = { _ in }
    var onConnected: (String?) -> Void = { _ in }
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
                    let name = try Wire.checkPCHello(data)
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
