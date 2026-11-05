import Foundation
import Network
let q = DispatchQueue.main
let l = try NWListener(using: .tcp, on: .any)
var c: NWConnection?; var server: NWConnection?
l.stateUpdateHandler = { state in
print("LISTENER", state, l.port as Any)
if case .ready = state {
let connection = NWConnection(host: "127.0.0.1", port: l.port!, using: .tcp); c = connection
connection.stateUpdateHandler = { s in print("CLIENT", s); if case .ready = s { exit(0) } }
connection.start(queue: q)
}
}
l.newConnectionHandler = { connection in server = connection; connection.stateUpdateHandler = { print("SERVER", $0) }; connection.start(queue: q) }
l.start(queue: q)
q.asyncAfter(deadline: .now() + 8) { exit(1) }
dispatchMain()
