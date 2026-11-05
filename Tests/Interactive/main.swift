import Foundation
import Network
var failures = 0
func check(_ value: Bool, _ name: String) { print(value ? "PASS:" : "FAIL:", name); if !value { failures += 1 } }
func pump(_ f: () -> Bool, seconds: Double = 8) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while !f(), Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
    return f()
}
let lock = NSLock()
var decoding = false, decoded = false, inputWhileDecoding = false, echoWhileDecoding = false
var actions: [Wire.Kind] = [], controls: [DesktopControlMessage.Action] = []
var inputBodies: [Data] = []
var connected = false, fastReady = false, ended = false
let engine = ReceiverEngine()
let channel = CursorChannel()
let q = DispatchQueue(label: "InteractiveTest", qos: .userInteractive)
let key = try newPairingKey()
let listener = try NWListener(using: networkParameters(key: key), on: .any)
var port: UInt16?
var server: Peer?
let template = try VideoFrame(Data(contentsOf: URL(fileURLWithPath: "build/CoreTests-sample.dat")))
engine.beforeDecode = {
    lock.lock(); decoding = true; lock.unlock()
    Thread.sleep(forTimeInterval: 0.7)
    lock.lock(); decoding = false; decoded = true; lock.unlock()
}
engine.onPixel = { _, done in done(.accepted) }
engine.onConnection = { value in DispatchQueue.main.async { connected = value; if !value && fastReady { ended = true } } }
engine.onInteractiveReady = { DispatchQueue.main.async { fastReady = true } }
engine.onDesktopControl = { message in DispatchQueue.main.async { controls.append(message.action) } }
engine.onCursor = { _, _, _, _ in lock.lock(); if decoding { echoWhileDecoding = true }; lock.unlock() }
listener.stateUpdateHandler = { state in if case .ready = state { DispatchQueue.main.async { port = listener.port?.rawValue } } }
listener.newConnectionHandler = { connection in
    let peer = Peer(connection, queue: q); server = peer
    peer.onReady = { peer.send(.hello, Wire.hello(role: "sender")) }
    peer.onPacket = { kind, data in
        if kind == .hello {
            do {
                _ = try Wire.checkHello(data, expected: "receiver")
                channel.onInput = { kind, body in
                    lock.lock(); actions.append(kind); inputBodies.append(body); if decoding { inputWhileDecoding = true }; lock.unlock()
                    if kind == .desktopControl, let m = try? DesktopControlMessage(body), m.action != .end {
                        channel.sendInput(.desktopControl, DesktopControlMessage(action: .accepted, token: m.token, width: 1920, height: 1080).serialize())
                    }
                    if kind == .desktopPointer {
                        var r = Reader(body); _ = try? r.u64()
                        if let value = try? r.rest() { var echo = Data([1,1]); echo.append(value); channel.sendPosition(echo) }
                    }
                }
                try channel.startServer { offer in peer.send(.cursorOffer, offer.data) }
            } catch { peer.end("\(error)") }
        }
    }
    peer.start()
}
listener.start(queue: q)
check(pump({ port != nil }), "interactive test listener ready")
try engine.connect(endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port!)!), key: key, previouslyApproved: true)
check(pump({ connected && fastReady }), "dedicated control authenticated after video hello")
q.async { server?.send(.video, VideoFrame(sequence: 1, timestamp: monotonicNS(), sps: template.sps, pps: template.pps, avcc: template.avcc).serialize()) }
check(pump({ lock.lock(); defer { lock.unlock() }; return decoding }), "deliberate decoder stall begins")
engine.sendDesktopControl(DesktopControlMessage(action: .begin, token: 123))
check(pump({ controls.contains(.accepted) }, seconds: 0.5), "desktop handshake is not blocked by decoder")
engine.sendPointer(PointerMessage(action: .move, x: 0.4, y: 0.5))
engine.sendPointer(PointerMessage(action: .leftDown, x: 0.4, y: 0.5))
engine.sendKeyboard(KeyboardMessage(action: .down, keyCode: 0))
engine.sendKeyboard(KeyboardMessage(action: .up, keyCode: 0))
engine.sendPointer(PointerMessage(action: .leftUp, x: 0.4, y: 0.5))
check(pump({ lock.lock(); defer { lock.unlock() }; return inputBodies.count >= 6 && echoWhileDecoding }, seconds: 0.5), "cursor and input traverse both directions during decoder stall")
lock.lock(); let kinds = actions; let whileBusy = inputWhileDecoding && echoWhileDecoding; let bodies = inputBodies; lock.unlock()
check(whileBusy, "700 ms decode stall cannot block independent cursor or input")
check(kinds == [.desktopControl, .desktopPointer, .desktopPointer, .desktopKeyboard, .desktopKeyboard, .desktopPointer], "click and keyboard ordering preserved on one input transport")
check(bodies.dropFirst().allSatisfy { var r = Reader($0); return (try? r.u64()) == 123 }, "every desktop event retains its lease token")
check(pump({ lock.lock(); defer { lock.unlock() }; return decoded }), "video decode completes after input")
channel.stop()
check(pump({ ended }), "input-channel failure tears down session instead of replaying clicks on video")
engine.stop(); listener.cancel(); server?.end(); channel.stop()
// A first movement is buffered briefly so a slow-to-open fast channel can win
// without reordering input already sent over the video connection.
let early = ReceiverEngine(), earlyChannel = CursorChannel()
let earlyListener = try NWListener(using: networkParameters(key: key), on: .any)
var earlyPort: NWEndpoint.Port?, earlyPeer: Peer?, earlyReady = false, earlyVideoMoves = 0, earlyFastMoves = 0
var earlyPending = false, earlyStates: [Bool] = []
early.onInteractiveReady = { DispatchQueue.main.async { earlyReady = true } }
early.onInteractivePending = { value in DispatchQueue.main.async { earlyPending = value } }
early.onInteractiveStateChanged = { value in DispatchQueue.main.async { earlyStates.append(value) } }
earlyListener.stateUpdateHandler = { if case .ready = $0 { DispatchQueue.main.async { earlyPort = earlyListener.port } } }
earlyListener.newConnectionHandler = { connection in
    let peer = Peer(connection, queue: q); earlyPeer = peer
    peer.onReady = { peer.send(.hello, Wire.hello(role: "sender")) }
    peer.onPacket = { kind, _ in
        if kind == .hello {
            q.asyncAfter(deadline: .now() + 0.04) {
                earlyChannel.onInput = { _, _ in DispatchQueue.main.async { earlyFastMoves += 1 } }
                do { try earlyChannel.startServer { offer in peer.send(.cursorOffer, offer.data) } }
                catch { peer.end("\(error)") }
            }
        } else if kind == .pointer { DispatchQueue.main.async { earlyVideoMoves += 1 } }
    }
    peer.start()
}
earlyListener.start(queue: q)
check(pump({ earlyPort != nil }), "delayed fast-channel listener ready")
try early.connect(endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: earlyPort!.rawValue)!), key: key, previouslyApproved: true)
check(pump({ early.queue.sync { early.phase == .preparing } }), "video connection starts before delayed fast channel")
early.sendPointer(PointerMessage(action: .move, x: 0.2, y: 0.3))
check(pump({ earlyReady && earlyFastMoves == 1 }), "initial movement waits for and uses the fast channel")
check(earlyVideoMoves == 0 && !earlyPending && earlyStates.last == true, "buffered movement is sent once, in order, on the fast route")
early.sendPointer(PointerMessage(action: .move, x: 0.3, y: 0.4))
check(pump({ earlyFastMoves == 2 }) && earlyVideoMoves == 0, "later movements remain on the selected fast route")
early.stop(); earlyListener.cancel(); earlyPeer?.end(); earlyChannel.stop()

// If the fast channel misses the short startup grace, pin the session to the
// video route; a late socket must not reorder movements across connections.
let fallback = ReceiverEngine(), lateChannel = CursorChannel()
let lateListener = try NWListener(using: networkParameters(key: key), on: .any)
var latePort: NWEndpoint.Port?, latePeer: Peer?, lateReady = false, videoMoves = 0, fastMoves = 0
var transportStates: [Bool] = []
fallback.onInteractiveReady = { DispatchQueue.main.async { lateReady = true } }
fallback.onInteractiveStateChanged = { value in DispatchQueue.main.async { transportStates.append(value) } }
lateListener.stateUpdateHandler = { if case .ready = $0 { DispatchQueue.main.async { latePort = lateListener.port } } }
lateListener.newConnectionHandler = { connection in
    let peer = Peer(connection, queue: q); latePeer = peer
    peer.onReady = { peer.send(.hello, Wire.hello(role: "sender")) }
    peer.onPacket = { kind, _ in
        if kind == .pointer {
            DispatchQueue.main.async { videoMoves += 1 }
            if !lateChannel.isReady {
                lateChannel.onInput = { _, _ in DispatchQueue.main.async { fastMoves += 1 } }
                do { try lateChannel.startServer { offer in peer.send(.cursorOffer, offer.data) } }
                catch { peer.end("\(error)") }
            }
        }
    }
    peer.start()
}
lateListener.start(queue: q)
check(pump({ latePort != nil }), "late control channel listener ready")
try fallback.connect(endpoint: .hostPort(host: "127.0.0.1", port: latePort!), key: key, previouslyApproved: true)
check(pump({ fallback.queue.sync { fallback.phase == .preparing } }), "late channel starts after an authenticated video transport")
fallback.sendPointer(PointerMessage(action: .move, x: 0.2, y: 0.3))
check(pump({ lateReady && videoMoves == 1 }), "timed-out startup grace safely falls back to video")
check(transportStates.last == false, "late socket readiness does not falsely report input switched to fast transport")
fallback.sendPointer(PointerMessage(action: .move, x: 0.3, y: 0.4))
check(pump({ videoMoves == 2 }) && fastMoves == 0, "late fast availability preserves the selected input ordering")
fallback.stop(); lateListener.cancel(); latePeer?.end(); lateChannel.stop()
print("RESULT:", failures, "failures; synthetic positions only, no system events posted")
exit(failures == 0 ? 0 : 1)
