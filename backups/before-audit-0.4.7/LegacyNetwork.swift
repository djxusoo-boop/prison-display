#if LEGACY
import Foundation
import Darwin

// High Sierra has no Network.framework. These deliberately small adapters
// implement only the operations used by PRISON DISPLAY, over nonblocking BSD
// sockets, public Bonjour APIs and the bundled OpenSSL TLS implementation.
struct IPv4Address: Hashable, CustomStringConvertible {
    let rawValue: Data
    init?(_ text: String) {
        var address = in_addr()
        guard inet_pton(AF_INET, text, &address) == 1 else { return nil }
        rawValue = withUnsafeBytes(of: &address) { Data($0) }
    }
    init?(_ bytes: Data) { guard bytes.count == 4 else { return nil }; rawValue = bytes }
    var description: String { rawValue.map(String.init).joined(separator: ".") }
}
struct NWInterface: Hashable {
    enum InterfaceType { case wifi, wiredEthernet, other }
    let name: String
    let type: InterfaceType
}
enum NWEndpoint: Hashable, CustomStringConvertible {
    enum Host: Hashable, CustomStringConvertible, ExpressibleByStringLiteral {
        case name(String, NWInterface?), ipv4(IPv4Address)
        init(_ name: String) { if let address = IPv4Address(name) { self = .ipv4(address) } else { self = .name(name, nil) } }
        init(stringLiteral value: String) { self.init(value) }
        var description: String { switch self { case .name(let name, _): return name; case .ipv4(let address): return address.description } }
    }
    struct Port: Hashable {
        let rawValue: UInt16
        init?(rawValue: UInt16) { self.rawValue = rawValue }
        static let any = Port(rawValue: 0)!
    }
    case hostPort(host: Host, port: Port)
    case service(name: String, type: String, domain: String, interface: NWInterface?)
    var description: String {
        switch self { case .hostPort(let host, let port): return "\(host):\(port.rawValue)"; case .service(let name, let type, let domain, _): return "\(name).\(type).\(domain)" }
    }
}
struct NWPath { let remoteEndpoint: NWEndpoint?; let availableInterfaces: [NWInterface] }
struct NWError: Error, CustomStringConvertible { let description: String; init(_ value: String) { description = value } }
enum NWProtocolIP {
    final class Options { enum Version { case any, v4 }; var version = Version.any }
}
final class NWParameters {
    enum ServiceClass { case interactiveVideo, interactiveVoice }
    final class Stack { var internetProtocol: AnyObject? = NWProtocolIP.Options() }
    let defaultProtocolStack = Stack()
    var includePeerToPeer = false
    var serviceClass = ServiceClass.interactiveVideo
    var requiredInterface: NWInterface?
    let secret: Data?
    init(secret: Data? = nil) { self.secret = secret }
    static var tcp: NWParameters { NWParameters() }
}

private func prepareSocket(_ fd: Int32) throws {
    guard fd >= 0 else { throw NWError("No se pudo abrir la conexión (\(errno)).") }
    guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) == 0,
          fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else { throw NWError("No se pudo preparar la conexión.") }
    var one: Int32 = 1
    guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size)) == 0,
          setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size)) == 0 else { throw NWError("No se pudo configurar la conexión interactiva.") }
}
private func remoteEndpoint(_ fd: Int32) -> NWEndpoint? {
    var address = sockaddr_in(), size = socklen_t(MemoryLayout<sockaddr_in>.size)
    let result = withUnsafeMutablePointer(to: &address) { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getpeername(fd, $0, &size) } }
    guard result == 0 else { return nil }
    var ip = address.sin_addr
    let bytes = withUnsafeBytes(of: &ip) { Data($0) }
    return .hostPort(host: .ipv4(IPv4Address(bytes)!), port: NWEndpoint.Port(rawValue: UInt16(bigEndian: address.sin_port))!)
}
private final class ServiceResolution: NSObject, NetServiceDelegate {
    private var service: NetService?
    private var completion: ((Result<(String, UInt16), NWError>) -> Void)?
    func start(name: String, type: String, domain: String, completion: @escaping (Result<(String, UInt16), NWError>) -> Void) {
        DispatchQueue.main.async {
            self.completion = completion
            let service = NetService(domain: domain, type: type, name: name); self.service = service
            service.delegate = self; service.resolve(withTimeout: 8)
        }
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName, sender.port > 0, sender.port <= 65535 else { finish(.failure(NWError("Bonjour devolvió una dirección inválida."))); return }
        finish(.success((host, UInt16(sender.port))))
    }
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) { finish(.failure(NWError("No se pudo resolver el otro Mac en la red."))) }
    private func finish(_ result: Result<(String, UInt16), NWError>) { let done = completion; completion = nil; service?.stop(); service = nil; done?(result) }
    func cancel() { DispatchQueue.main.async { self.completion = nil; self.service?.stop(); self.service = nil } }
}

final class NWConnection {
    enum State { case setup, preparing, ready, failed(NWError), waiting(NWError), cancelled }
    enum SendCompletion { case contentProcessed((NWError?) -> Void) }
    struct ContentContext {}
    let endpoint: NWEndpoint
    private let parameters: NWParameters
    private let server: Bool
    var stateUpdateHandler: ((State) -> Void)?
    private(set) var currentPath: NWPath?
    private var queue: DispatchQueue?
    private var fd: Int32 = -1
    private var tls: UnsafeMutableRawPointer?
    private var resolving: ServiceResolution?
    private var reader: DispatchSourceRead?
    private var writer: DispatchSourceWrite?
    private var readSuspended = true, writeSuspended = true
    private var closed = false, started = false, connecting = false, ready = false
    private var receiveCallback: ((Data?, ContentContext?, Bool, NWError?) -> Void)?
    private var receiveMaximum = 65536
    private var sends: [(Data, Int, (NWError?) -> Void)] = []
    private var queuedBytes = 0
    init(to endpoint: NWEndpoint, using parameters: NWParameters) { self.endpoint = endpoint; self.parameters = parameters; server = false }
    convenience init(host: NWEndpoint.Host, port: NWEndpoint.Port, using parameters: NWParameters) { self.init(to: .hostPort(host: host, port: port), using: parameters) }
    fileprivate init(accepted fd: Int32, using parameters: NWParameters) {
        self.fd = fd; self.parameters = parameters; server = true
        endpoint = remoteEndpoint(fd) ?? .hostPort(host: .init("127.0.0.1"), port: .any)
    }
    func start(queue: DispatchQueue) {
        guard !started else { return }; started = true; self.queue = queue
        queue.async {
            guard !self.closed else { return }
            self.stateUpdateHandler?(.preparing)
            if self.server { self.configureConnectedSocket(); return }
            switch self.endpoint {
            case .hostPort(let host, let port): self.resolveHost(host.description, port.rawValue)
            case .service(let name, let type, let domain, _):
                let resolution = ServiceResolution(); self.resolving = resolution
                resolution.start(name: name, type: type, domain: domain) { [weak self] result in
                    queue.async { guard let self = self, !self.closed else { return }; self.resolving = nil
                        switch result { case .success(let target): self.resolveHost(target.0, target.1); case .failure(let error): self.fail(error) }
                    }
                }
            }
            queue.asyncAfter(deadline: .now()+10) { [weak self] in
                guard let self = self, !self.closed, !self.ready else { return }; self.fail(NWError("El otro Mac no respondió a tiempo."))
            }
        }
    }
    private func resolveHost(_ host: String, _ port: UInt16) {
        guard let queue = queue else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var hints = addrinfo(); hints.ai_family = AF_INET; hints.ai_socktype = SOCK_STREAM; hints.ai_protocol = IPPROTO_TCP
            var info: UnsafeMutablePointer<addrinfo>?
            let result = getaddrinfo(host, String(port), &hints, &info)
            var addresses: [Data] = []
            if result == 0 {
                var item = info
                while let pointer = item {
                    if let address = pointer.pointee.ai_addr { addresses.append(Data(bytes: address, count: Int(pointer.pointee.ai_addrlen))) }
                    item = pointer.pointee.ai_next
                }
            }
            if let info = info { freeaddrinfo(info) }
            queue.async {
                guard let self = self, !self.closed else { return }
                guard result == 0, !addresses.isEmpty else { self.fail(NWError("No se encuentra el otro Mac en la red.")); return }
                for address in addresses {
                    let socketFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
                    do { try prepareSocket(socketFD) } catch { if socketFD >= 0 { Darwin.close(socketFD) }; continue }
                    let connected = address.withUnsafeBytes { Darwin.connect(socketFD, $0.baseAddress!.assumingMemoryBound(to: sockaddr.self), socklen_t(address.count)) }
                    if connected == 0 || errno == EINPROGRESS {
                        self.fd = socketFD; self.connecting = connected != 0; self.installSources()
                        if !self.connecting { self.configureConnectedSocket() } else { self.monitor(read: true, write: true) }
                        return
                    }
                    Darwin.close(socketFD)
                }
                self.fail(NWError("No se pudo llegar al otro Mac (\(errno))."))
            }
        }
    }
    private func installSources() {
        guard reader == nil, let queue = queue else { return }
        let read = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let write = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: queue)
        read.setEventHandler { [weak self] in self?.pump() }; write.setEventHandler { [weak self] in self?.pump() }
        reader = read; writer = write; readSuspended = true; writeSuspended = true
    }
    private func configureConnectedSocket() {
        do { try prepareSocket(fd) } catch { fail(NWError("\(error)")); return }
        var service: Int32 = parameters.serviceClass == .interactiveVoice ? NET_SERVICE_TYPE_VO : NET_SERVICE_TYPE_VI
        _ = setsockopt(fd, SOL_SOCKET, SO_NET_SERVICE_TYPE, &service, socklen_t(MemoryLayout<Int32>.size))
        connecting = false; installSources()
        currentPath = NWPath(remoteEndpoint: remoteEndpoint(fd), availableInterfaces: [])
        if let secret = parameters.secret {
            guard let object = ADTLSNew(fd, server, secret) else { fail(NWError("No se pudo preparar TLS cifrado.")); return }
            tls = object
        }
        pump()
    }
    private func monitor(read: Bool, write: Bool) {
        guard !closed else { return }
        if read && readSuspended { readSuspended = false; reader?.resume() }
        else if !read && !readSuspended { readSuspended = true; reader?.suspend() }
        if write && writeSuspended { writeSuspended = false; writer?.resume() }
        else if !write && !writeSuspended { writeSuspended = true; writer?.suspend() }
    }
    private func pump() {
        guard !closed, fd >= 0 else { return }
        if connecting {
            var error: Int32 = 0, length = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0, error == 0 else { fail(NWError("El otro Mac rechazó la conexión (\(error)).")); return }
            // Writable/readable notification confirms completion of connect.
            configureConnectedSocket(); return
        }
        if !ready {
            if let tls = tls {
                let result = ADTLSHandshake(tls)
                if result == -2 || result == -3 { monitor(read: true, write: result == -3); return }
                guard result == 1 else { fail(NWError("TLS rechazó la conexión: comprueba la clave y la versión.")); return }
            }
            ready = true; stateUpdateHandler?(.ready)
            guard !closed else { return }
        }
        var needsRead = receiveCallback != nil, needsWrite = false
        var writtenThisTurn = 0, continueWriting = false
        // A writable dispatch source need not notify again while the socket
        // stays writable. OpenSSL's partial-write mode emits one TLS record;
        // stopping after that record stalled large images until the next ping.
        // Drain to WANT_READ/WRITE, yielding explicitly after a bounded budget.
        while !sends.isEmpty && !closed {
            var item = sends[0]
            let result: Int32 = item.0.withUnsafeBytes { bytes in
                let base = bytes.baseAddress!.advanced(by: item.1), count = min(item.0.count-item.1, 65536)
                if let tls = tls { return ADTLSWrite(tls, base, Int32(count)) }
                let value = Darwin.send(fd, base, count, 0)
                if value < 0 && (errno == EWOULDBLOCK || errno == EAGAIN) { return -3 }
                return Int32(value)
            }
            if result > 0 {
                item.1 += Int(result); queuedBytes -= Int(result)
                if item.1 == item.0.count { sends.removeFirst(); item.2(nil) } else { sends[0] = item }
                writtenThisTurn += Int(result)
                if !sends.isEmpty && writtenThisTurn >= 262144 { continueWriting = true; break }
            } else if result == -2 { needsRead = true; break }
            else if result == -3 { needsWrite = true; break }
            else { fail(NWError("La conexión se interrumpió durante el envío.")); return }
        }
        guard !closed else { return }
        if let callback = receiveCallback {
            var bytes = [UInt8](repeating: 0, count: receiveMaximum)
            let result: Int32 = bytes.withUnsafeMutableBytes { buffer in
                if let tls = tls { return ADTLSRead(tls, buffer.baseAddress!, Int32(buffer.count)) }
                let value = Darwin.recv(fd, buffer.baseAddress!, buffer.count, 0)
                if value < 0 && (errno == EWOULDBLOCK || errno == EAGAIN) { return -2 }
                return Int32(value)
            }
            if result > 0 { receiveCallback = nil; callback(Data(bytes.prefix(Int(result))), nil, false, nil); needsRead = false }
            else if result == -3 { needsWrite = true }
            else if result == 0 { receiveCallback = nil; callback(nil, nil, true, nil); cleanup(); return }
            else if result != -2 { fail(NWError("La conexión se interrumpió durante la recepción.")); return }
        }
        monitor(read: needsRead, write: needsWrite)
        if continueWriting { queue?.async { [weak self] in self?.pump() } }
    }
    func send(content: Data?, completion: SendCompletion) {
        guard let queue = queue else { return }
        queue.async {
            guard case .contentProcessed(let done) = completion else { return }
            guard !self.closed, let content = content, !content.isEmpty, content.count <= Wire.maxPacket+4, self.queuedBytes+content.count <= 2*(Wire.maxPacket+4) else { done(NWError("Envío cancelado o demasiado grande.")); return }
            self.sends.append((content, 0, done)); self.queuedBytes += content.count; self.pump()
        }
    }
    func receive(minimumIncompleteLength: Int, maximumLength: Int, completion: @escaping (Data?, ContentContext?, Bool, NWError?) -> Void) {
        guard let queue = queue else { return }
        queue.async {
            guard !self.closed else { completion(nil, nil, true, nil); return }
            guard self.receiveCallback == nil else { completion(nil, nil, false, NWError("Recepción duplicada.")); return }
            self.receiveMaximum = min(65536, max(1, maximumLength)); self.receiveCallback = completion; self.pump()
        }
    }
    private func fail(_ error: NWError) { guard !closed else { return }; cleanup(); stateUpdateHandler?(.failed(error)) }
    private func cleanup() {
        guard !closed else { return }; closed = true; resolving?.cancel(); resolving = nil
        if readSuspended { reader?.resume() }; if writeSuspended { writer?.resume() }
        reader?.cancel(); writer?.cancel(); reader = nil; writer = nil
        if let tls = tls { ADTLSFree(tls); self.tls = nil }
        if fd >= 0 { Darwin.close(fd); fd = -1 }
        receiveCallback = nil
        let pending = sends; sends.removeAll(); queuedBytes = 0
        for item in pending { item.2(NWError("Conexión cerrada.")) }
    }
    func cancel() {
        if let queue = queue { queue.async { guard !self.closed else { return }; self.cleanup(); self.stateUpdateHandler?(.cancelled) } }
        else { if fd >= 0 { Darwin.close(fd); fd = -1 }; closed = true }
    }
    deinit {
        if readSuspended { reader?.resume() }; if writeSuspended { writer?.resume() }
        reader?.cancel(); writer?.cancel(); if let tls = tls { ADTLSFree(tls) }; if fd >= 0 { Darwin.close(fd) }
    }
}

final class NWListener {
    struct Service { let name: String; let type: String }
    enum State { case setup, ready, failed(NWError), cancelled }
    var service: Service?
    var stateUpdateHandler: ((State) -> Void)?
    var newConnectionHandler: ((NWConnection) -> Void)?
    private(set) var port: NWEndpoint.Port?
    private let parameters: NWParameters
    private var fd: Int32
    private var source: DispatchSourceRead?
    private var queue: DispatchQueue?
    private var publisher: NetService?
    private let lifetime = NSLock()
    private var closed = false
    private var alive: Bool { lifetime.lock(); defer { lifetime.unlock() }; return !closed }
    init(using parameters: NWParameters, on port: NWEndpoint.Port) throws {
        self.parameters = parameters; fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        do {
            try prepareSocket(fd); var reuse: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
            var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET); address.sin_port = port.rawValue.bigEndian
            let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
            guard bound == 0, Darwin.listen(fd, 8) == 0 else { throw NWError("No se pudo abrir el puerto de pantalla (\(errno)).") }
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            guard withUnsafeMutablePointer(to: &address, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }) == 0 else { throw NWError("No se pudo leer el puerto de pantalla.") }
            self.port = NWEndpoint.Port(rawValue: UInt16(bigEndian: address.sin_port))
        } catch { if fd >= 0 { Darwin.close(fd); fd = -1 }; throw error }
    }
    func start(queue: DispatchQueue) {
        self.queue = queue
        queue.async {
            guard self.alive, self.source == nil else { return }
            let source = DispatchSource.makeReadSource(fileDescriptor: self.fd, queue: queue); self.source = source
            source.setEventHandler { [weak self] in
                guard let self = self, self.alive else { return }
                for _ in 0..<8 {
                    let accepted = Darwin.accept(self.fd, nil, nil)
                    if accepted < 0 { break }
                    let connection = NWConnection(accepted: accepted, using: self.parameters)
                    if let handler = self.newConnectionHandler { handler(connection) } else { connection.cancel() }
                }
            }
            source.resume()
            if let service = self.service, let port = self.port {
                DispatchQueue.main.async {
                    guard self.alive else { return }
                    let publisher = NetService(domain: "local.", type: service.type, name: service.name, port: Int32(port.rawValue)); self.publisher = publisher; publisher.publish()
                }
            }
            self.stateUpdateHandler?(.ready)
        }
    }
    func cancel() {
        lifetime.lock(); let wasClosed = closed; closed = true; lifetime.unlock(); guard !wasClosed else { return }
        let cleanup = {
            self.source?.cancel(); self.source = nil; if self.fd >= 0 { Darwin.close(self.fd); self.fd = -1 }
            DispatchQueue.main.async { self.publisher?.stop(); self.publisher = nil }
            self.stateUpdateHandler?(.cancelled)
        }
        if let queue = queue { queue.async(execute: cleanup) } else { cleanup() }
    }
    deinit { source?.cancel(); if fd >= 0 { Darwin.close(fd) } }
}

final class NWBrowser: NSObject, NetServiceBrowserDelegate {
    enum Descriptor { case bonjour(type: String, domain: String?) }
    enum State { case ready, failed(NWError), cancelled }
    struct Result: Hashable { let endpoint: NWEndpoint; let interfaces: Set<NWInterface> }
    var browseResultsChangedHandler: ((Set<Result>, [Int]) -> Void)?
    var stateUpdateHandler: ((State) -> Void)?
    private let descriptor: Descriptor
    private var queue: DispatchQueue?
    private var browser: NetServiceBrowser?
    private var services: Set<Result> = []
    private let lifetime = NSLock()
    private var closed = false
    private var alive: Bool { lifetime.lock(); defer { lifetime.unlock() }; return !closed }
    init(for descriptor: Descriptor, using parameters: NWParameters) { self.descriptor = descriptor; super.init() }
    func start(queue: DispatchQueue) {
        self.queue = queue
        DispatchQueue.main.async {
            guard self.alive, self.browser == nil else { return }
            let browser = NetServiceBrowser(); self.browser = browser; browser.delegate = self
            if case .bonjour(let type, let domain) = self.descriptor { browser.searchForServices(ofType: type, inDomain: domain ?? "local.") }
        }
    }
    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) { queue?.async { if self.alive { self.stateUpdateHandler?(.ready) } } }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.insert(Result(endpoint: .service(name: service.name, type: service.type, domain: service.domain, interface: nil), interfaces: [])); deliver()
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.remove(Result(endpoint: .service(name: service.name, type: service.type, domain: service.domain, interface: nil), interfaces: [])); deliver()
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        queue?.async { if self.alive { self.stateUpdateHandler?(.failed(NWError("No se pudo buscar Macs en Bonjour."))) } }
    }
    private func deliver() { let snapshot = services; queue?.async { if self.alive { self.browseResultsChangedHandler?(snapshot, []) } } }
    func cancel() {
        lifetime.lock(); closed = true; lifetime.unlock()
        DispatchQueue.main.async { self.browser?.stop(); self.browser = nil; self.services.removeAll() }
    }
}
#endif
