import Foundation
import Network
let q = DispatchQueue(label:"PrisonInputBenchmark",qos:.userInteractive)
let key = try newPairingKey()
let listener = try NWListener(using:networkParameters(key:key),on:.any)
let template = try VideoFrame(Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2])))
let channel = CursorChannel()
var current: Peer?
var sequence: UInt64 = 0
var inflight = false
var authenticated = false
var finished = false
let lock = NSLock()
listener.stateUpdateHandler = { state in
    print("LISTENER", state)
    if case .ready = state, let port = listener.port?.rawValue {
        let link = try! ConnectionLink(host:CommandLine.arguments[3],port:port,key:key)
        try! link.url.absoluteString.write(toFile:CommandLine.arguments[1],atomically:true,encoding:.utf8)
        try! FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:CommandLine.arguments[1])
    }
}
listener.newConnectionHandler = { connection in
    let peer = Peer(connection,queue:q); current = peer
    peer.onReady = { peer.send(.hello,Wire.hello(role:"sender")) }
    peer.onPacket = { kind,data in
        do {
            switch kind {
            case .hello:
                _ = try Wire.checkHello(data,expected:"receiver"); authenticated = true
                channel.onInput = { kind, body in
                    do {
                        if kind == .desktopControl {
                            let m = try DesktopControlMessage(body)
                            if m.action != .end { channel.sendInput(.desktopControl,DesktopControlMessage(action:.accepted,token:m.token,width:1920,height:1080).serialize()) }
                        } else if kind == .desktopPointer {
                            var r = Reader(body); _ = try r.u64(); let m = try PointerMessage(r.rest())
                            var echo = Data([1,1]);echo.append(m.serialize());channel.sendPosition(echo)
                        }
                    } catch { print("ERROR",error);peer.end() }
                }
                try channel.startServer { peer.send(.cursorOffer,$0.data) }
            case .desktopControl:
                let m = try DesktopControlMessage(data)
                if m.action != .end { peer.send(.desktopControl,DesktopControlMessage(action:.accepted,token:m.token,width:1920,height:1080).serialize()) }
            case .desktopPointer:
                var r = Reader(data); _ = try r.u64(); let m = try PointerMessage(r.rest())
                // Echo simulated positions only; never inject input into either desktop.
                var echo = Data([1,1]); echo.append(m.serialize()); peer.send(.cursor,echo)
            case .ack: inflight = false
            case .keyboard,.desktopKeyboard,.pointer: break
            default: throw AireError("Unexpected benchmark packet")
            }
        } catch { print("ERROR",error); peer.end(); lock.lock();finished = true;lock.unlock() }
    }
    peer.onEnd = { reason in print("END", reason); lock.lock();finished = true;lock.unlock() }
    peer.start()
}
let video = DispatchSource.makeTimerSource(queue:q)
video.schedule(deadline:.now()+1,repeating:.milliseconds(16))
video.setEventHandler {
    guard let peer = current, authenticated, !inflight else { return }
    inflight = true; sequence += 1
    peer.send(.video,VideoFrame(sequence:sequence,timestamp:monotonicNS(),sps:template.sps,pps:template.pps,avcc:template.avcc).serialize())
}
listener.start(queue:q); video.resume()
let end = Date().addingTimeInterval(50)
while Date() < end {
    lock.lock(); let done = finished; lock.unlock(); if done { break }
    RunLoop.current.run(until:Date().addingTimeInterval(0.01))
}
video.cancel(); listener.cancel(); print("PASS: simulated control echo; no desktop input posted")
