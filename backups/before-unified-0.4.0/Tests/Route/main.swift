import Foundation
import Network

let host = CommandLine.arguments[1]
let port = NWEndpoint.Port(rawValue: UInt16(CommandLine.arguments[2])!)!
let streamPort = NWEndpoint.Port(rawValue: UInt16(CommandLine.arguments[3])!)!
let useResolvedAddress = CommandLine.arguments.count > 4 && CommandLine.arguments[4] == "literal"
let q = DispatchQueue.main
var connections: [NWConnection] = []
var done = false
var succeeded = false
func describe(_ host: NWEndpoint.Host) -> String {
    switch host {
    case .ipv6(let address): return "ipv6=\(address), interface=\(address.interface?.name ?? "nil")"
    case .ipv4(let address): return "ipv4=\(address)"
    case .name(let name, let interface): return "name=\(name), interface=\(interface?.name ?? "nil")"
    @unknown default: return "unknown"
    }
}
let original = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
connections.append(original)
original.stateUpdateHandler = { state in
    print("ORIGINAL", state)
    if case .ready = state {
        guard let endpoint = original.currentPath?.remoteEndpoint, case .hostPort(let resolved, _) = endpoint else { done = true; return }
        print("RESOLVED", describe(resolved))
        let parsed = NWEndpoint.Host(useResolvedAddress ? "\(resolved)" : host)
        print("REPARSED", describe(parsed))
        let parameters = NWParameters.tcp
        if case .ipv6(let address) = parsed { parameters.requiredInterface = address.interface }
        original.cancel()
        let second = NWConnection(host: parsed, port: streamPort, using: parameters)
        connections.append(second)
        second.stateUpdateHandler = { state in
            print("REPARSED STATE", state)
            switch state { case .ready: succeeded = true; done = true; case .failed, .waiting: done = true; default: break }
        }
        second.start(queue: q)
    }
    switch state { case .failed, .waiting: done = true; default: break }
}
original.start(queue: q)
let end = Date().addingTimeInterval(12)
while !done && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
connections.forEach { $0.cancel() }
exit(succeeded ? 0 : 1)
