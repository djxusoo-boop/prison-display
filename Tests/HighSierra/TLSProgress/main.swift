import Foundation
setbuf(stdout, nil)
var failures = 0
func check(_ ok: Bool, _ text: String) { print(ok ? "PASS:" : "FAIL:", text); if !ok { failures += 1 } }
func pump(_ condition: () -> Bool, seconds: Double = 5) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while !condition() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.002)) }
    return condition()
}
do {
    let queue = DispatchQueue(label: "TLSProgress.raw")
    let parameters = try networkParameters(key: newPairingKey())
    let listener = try NWListener(using: parameters, on: .any)
    var port: NWEndpoint.Port?, client: NWConnection?, server: NWConnection?
    var ready = false, error: String?
    listener.stateUpdateHandler = { state in
        if case .ready = state { DispatchQueue.main.async { port = listener.port } }
        if case .failed(let e) = state { DispatchQueue.main.async { error = "\(e)" } }
    }
    listener.newConnectionHandler = { incoming in
        server = incoming
        incoming.stateUpdateHandler = { state in
            if case .failed(let e) = state { DispatchQueue.main.async { error = "\(e)" } }
        }
        incoming.start(queue: queue)
    }
    listener.start(queue: queue)
    check(pump({ port != nil || error != nil }) && port != nil, "raw TLS listener starts")
    if let port = port {
        let outgoing = NWConnection(host: "127.0.0.1", port: port, using: parameters); client = outgoing
        outgoing.stateUpdateHandler = { state in
            if case .ready = state { DispatchQueue.main.async { ready = true } }
            if case .failed(let e) = state { DispatchQueue.main.async { error = "\(e)" } }
        }
        outgoing.start(queue: queue)
        check(pump({ ready || error != nil }) && ready && error == nil, "raw TLS authenticates without Peer heartbeat")
        for size in [1_048_699, 4_000_000] {
            let payload = Data((0..<size).map { UInt8(truncatingIfNeeded: $0*37) })
            for reverse in [false, true] {
                var bytes = Data(), completed = false, sent = false
                let transmit = reverse ? server! : outgoing, receive = reverse ? outgoing : server!
                func read() {
                    receive.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, done, problem in
                        if let data = data { bytes.append(data) }
                        if let problem = problem { DispatchQueue.main.async { error = "\(problem)" }; return }
                        if bytes.count == payload.count { DispatchQueue.main.async { completed = true }; return }
                        if done || bytes.count > payload.count { DispatchQueue.main.async { error = "Unexpected EOF/overflow" }; return }
                        read()
                    }
                }
                read(); let began = Date()
                transmit.send(content: payload, completion: .contentProcessed { problem in
                    DispatchQueue.main.async { if let problem = problem { error = "\(problem)" }; sent = problem == nil }
                })
                let success = pump({ (completed && sent) || error != nil }) && completed && sent && error == nil
                check(success && bytes == payload, "single \(size)-byte packet progresses \(reverse ? "server→client" : "client→server") without a ping or additional sends")
                print("TRANSFER seconds", Date().timeIntervalSince(began))
                if !success { break }
            }
            if error != nil { break }
        }
    }
    client?.cancel(); server?.cancel(); listener.cancel()
    if let error = error { check(false, error) }
} catch { check(false, "Unexpected: \(error)") }
print("RESULT:", failures, "failures; raw encrypted sockets, no video or OS input")
exit(failures == 0 ? 0 : 1)
