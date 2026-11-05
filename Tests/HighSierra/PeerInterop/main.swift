import Foundation
#if !LEGACY
import Network
#endif
setbuf(stdout, nil)
let arguments = CommandLine.arguments
let serverMode = arguments[1] == "serve"
let key = try String(contentsOfFile: arguments[2]).trimmingCharacters(in: .whitespacesAndNewlines)
let parameters = try networkParameters(key: key)
let queue = DispatchQueue(label: "PeerInterop", qos: .userInteractive)
let payload = Data(repeating: 0x7e, count: 1_048_576)
var peer: Peer?, listener: NWListener?, received = 0, done = false, failure: String?, began: UInt64 = 0
var rtts: [Double] = []
func attach(_ connection: NWConnection) {
    let p = Peer(connection, queue: queue); peer = p
    p.onReady = { p.send(.hello, Wire.hello(role: serverMode ? "sender" : "receiver")) }
    p.onPacket = { kind, data in
        if kind == .hello {
            if !serverMode { began = monotonicNS(); p.send(.video, payload) }
        } else if kind == .video {
            guard data == payload else { failure = "Payload mismatch"; done = true; return }
            received += 1
            if serverMode { p.send(.video, data) }
            else {
                let elapsed = Double(monotonicNS()-began)/1e6; rtts.append(elapsed); print("ECHO", received, "ms", elapsed)
                if received == 10 { done = true } else { began = monotonicNS(); p.send(.video, payload) }
            }
        }
    }
    p.onEnd = { reason in if serverMode && received == 10 { done = true } else if !done { failure = reason; done = true } }
    p.start()
}
if serverMode {
    let l = try NWListener(using: parameters, on: .any); listener = l
    l.newConnectionHandler = attach
    l.stateUpdateHandler = { state in if case .ready = state, let port = l.port {
        try! String(port.rawValue).write(toFile: arguments[3], atomically: true, encoding: .utf8); print("READY",port.rawValue)
    } }
    l.start(queue: queue)
} else { attach(NWConnection(host: NWEndpoint.Host(arguments[3]), port: NWEndpoint.Port(rawValue: UInt16(arguments[4])!)!, using: parameters)) }
let deadline = Date().addingTimeInterval(90)
while !done && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.002)) }
peer?.end(); listener?.cancel()
rtts.sort()
print("RESULT", received == 10 && failure == nil ? "PASS" : "FAIL", "payloads", received, "MiB", received, "medianMS", rtts.isEmpty ? 0 : rtts[rtts.count/2], "error",failure ?? "none")
exit(received == 10 && failure == nil ? 0 : 1)
