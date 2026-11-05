import Foundation
import Network
var failures = 0
func check(_ value: Bool, _ name: String) { print(value ? "PASS:" : "FAIL:", name); if !value { failures += 1 } }
let queue = PriorityPacketQueue()
let images = (1...3).map { Data([UInt8($0)]) }
for image in images { queue.append(.video, image, completion: nil) }
check(queue.take()?.body == images[0], "first frame is already being sent")
queue.append(.cursor, Data([90]), completion: nil)
check(queue.take()?.kind == .cursor, "cursor passes two waiting frames at the next packet boundary")
check(queue.take()?.body == images[1] && queue.take()?.body == images[2], "H264 dependent frames keep their order and are never dropped")
queue.append(.hello, Data(), completion: nil)
queue.append(.video, images[0], completion: nil)
queue.append(.pointer, Data([1]), completion: nil)
queue.append(.cursor, Data([91]), completion: nil)
check(queue.take()?.kind == .hello && queue.take()?.kind == .video && queue.take()?.kind == .pointer && queue.take()?.kind == .cursor, "cursor cannot cross a handshake or click barrier")
var actualPosition = Data([40])
queue.append(.video, images[0], completion: nil)
queue.appendCursor({ actualPosition }, completion: nil)
actualPosition = Data([80])
check(queue.take()?.body == Data([80]), "cursor is sampled at send time after a transport stall, not when queued")
_ = queue.take()
var completed = 0
queue.append(.cursor, Data(), completion: { completed += 1 })
queue.take()?.completion?()
check(completed == 1, "send completion remains attached to the chosen packet")
queue.append(.cursor, Data(), completion: nil); queue.clear()
check(queue.take() == nil, "disconnect removes unsent cursor and frames")
let input: [(Wire.Kind, Data)] = [(.hello, Data()), (.video, images[0]), (.cursor, Data([90])), (.video, images[1]), (.cursor, Data([91])), (.ack, Data()), (.video, images[2])]
let output = cursorFirst(input)
check(output.map { $0.0 } == [.hello, .cursor, .cursor, .video, .video, .ack, .video], "received cursor positions are processed before queued video decode")
check(output.filter { $0.0 == .video }.map { $0.1 } == images, "receive priority preserves every frame and its sequence")
check(output.filter { $0.0 == .cursor }.map { $0.1 } == [Data([90]), Data([91])], "latest position is delivered last, never overwritten by stale cursor")
var parser = PacketParser()
let encoded = output.reduce(Data()) { $0 + Wire.packet($1.0, $1.1) }
var decoded: [(Wire.Kind, Data)] = []
do {
    for byte in encoded { decoded += try parser.feed(Data([byte])) }
    check(decoded.map { $0.0 } == output.map { $0.0 } && decoded.map { $0.1 } == output.map { $0.1 }, "priority packets survive bytewise network fragmentation")
} catch { check(false, "fragmented priority packets parse") }
func pump(_ condition: () -> Bool, seconds: Double = 10) -> Bool {
    let limit = Date().addingTimeInterval(seconds)
    while !condition() && Date() < limit { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
    return condition()
}
do {
    let transportQueue = DispatchQueue(label: "PriorityTests.TLS")
    let key = try newPairingKey()
    let listener = try NWListener(using: networkParameters(key: key), on: .any)
    var port: NWEndpoint.Port?
    var server: Peer?
    var received: [(Wire.Kind, Data)] = []
    listener.stateUpdateHandler = { state in
        if case .ready = state { DispatchQueue.main.async { port = listener.port } }
    }
    listener.newConnectionHandler = { connection in
        let peer = Peer(connection, queue: transportQueue); server = peer
        peer.onPacket = { kind, _ in
            guard kind == .hello else { return }
            peer.send(.hello, Wire.hello(role: "sender"))
            for image in images { peer.send(.video, image) }
            var position = Data([40])
            peer.sendCursor({ position })
            position = Data([80])
        }
        peer.start()
    }
    listener.start(queue: transportQueue)
    check(pump({ port != nil }), "encrypted priority listener ready")
    if let port = port {
        let client = Peer(NWConnection(host: "127.0.0.1", port: port, using: try networkParameters(key: key)), queue: transportQueue)
        client.onReady = { client.send(.hello, Wire.hello(role: "receiver")) }
        client.onPacket = { kind, body in DispatchQueue.main.async { received.append((kind, body)) } }
        client.start()
        check(pump({ received.count == 5 }), "TLS delivers handshake, newest cursor and all three frames")
        check(received.first?.0 == .hello, "TLS handshake remains ahead of cursor")
        check(received.filter { $0.0 == .cursor }.map { $0.1 } == [Data([80])], "real Peer resolves the newest cursor at send time")
        check(received.filter { $0.0 == .video }.map { $0.1 } == images, "real encrypted transport retains H264 frame sequence")
        transportQueue.async { client.end(); server?.end(); listener.cancel() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    } else { listener.cancel() }
} catch { print("ERROR", error); failures += 1 }
func moveBody(_ value: UInt8, token: UInt64? = nil, action: UInt8 = 0) -> Data {
    var result = Data(); if let token = token { result.u64(token) }
    var body = Data(repeating: value, count: Wire.pointerSize); body[0] = action; result.append(body); return result
}
let moves = PriorityPacketQueue()
for n in 1...200 { moves.append(.pointer, moveBody(UInt8(n)), completion: nil) }
check(moves.take()?.body == moveBody(200) && moves.take() == nil, "slow socket retains only latest unsent pointer instead of 200 old positions")
moves.append(.pointer,moveBody(1),completion:nil)
moves.append(.pointer,moveBody(2,action:1),completion:nil)
moves.append(.pointer,moveBody(3),completion:nil)
moves.append(.pointer,moveBody(4),completion:nil)
moves.append(.pointer,moveBody(5,action:2),completion:nil)
var order: [Data] = []; while let value = moves.take() { order.append(value.body) }
check(order == [moveBody(1),moveBody(2,action:1),moveBody(4),moveBody(5,action:2)], "coalescing preserves click, newest drag and release order")
moves.append(.desktopPointer,moveBody(1,token:1),completion:nil)
moves.append(.desktopPointer,moveBody(2,token:2),completion:nil)
moves.append(.desktopPointer,moveBody(3,token:2),completion:nil)
check(moves.take()?.body == moveBody(1,token:1) && moves.take()?.body == moveBody(3,token:2), "positions never merge across desktop control leases")
moves.append(.desktopPointer,moveBody(1,token:3),completion:nil)
moves.append(.desktopControl,Data([1]),completion:nil)
moves.append(.desktopPointer,moveBody(2,token:3),completion:nil)
check(moves.take()?.body == moveBody(1,token:3) && moves.take()?.kind == .desktopControl && moves.take()?.body == moveBody(2,token:3), "lease barrier retains positions on each side")
moves.append(.pointer,moveBody(1),completion:{})
moves.append(.pointer,moveBody(2),completion:nil)
check(moves.take()?.body == moveBody(1) && moves.take()?.body == moveBody(2), "completion-bearing input is never discarded")
let receivedMoves: [(Wire.Kind, Data)] = (1...200).map { (.pointer, moveBody($0)) }
let condensed = recentMovements(receivedMoves)
check(condensed.count == 1 && condensed.first?.1 == moveBody(200), "a buffered receive applies only its latest adjacent movement")
let barriers: [(Wire.Kind, Data)] = [(.desktopPointer, moveBody(1,token:1)), (.desktopPointer, moveBody(2,token:1)), (.desktopPointer, moveBody(3,token:1,action:1)), (.desktopPointer, moveBody(4,token:1)), (.desktopKeyboard, Data([0])), (.desktopPointer, moveBody(5,token:1)), (.desktopPointer, moveBody(6,token:2))]
let retained = recentMovements(barriers)
check(retained.map { $0.1 } == Array(barriers.dropFirst()).map { $0.1 }, "receive coalescing preserves clicks, keyboard and different lease tokens")
func deliveryBody(_ value: Int, token: UInt64? = nil, action: UInt8 = 0) -> Data {
    var d = Data(); if let token = token { d.u64(token) }
    d.append(action); d.u64((Double(value)/4096).bitPattern); d.u64(Double(0.5).bitPattern)
    d.u64(Double(0).bitPattern); d.append(1); d.u64(Double(0).bitPattern); d.u64(0)
    return d
}
let deliveryQueue = DispatchQueue(label: "input-delivery-stall")
let blocked = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
deliveryQueue.async { blocked.signal(); _ = release.wait(timeout: .now()+3) }
_ = blocked.wait(timeout: .now()+1)
let deliveryLock = NSLock()
var delivered: [(Wire.Kind, Data)] = [], overflows = 0
let delivery = OrderedInputDelivery(queue: deliveryQueue, receive: { kind, body in
    deliveryLock.lock(); delivered.append((kind,body)); deliveryLock.unlock()
}, overflow: { deliveryLock.lock(); overflows += 1; deliveryLock.unlock() })
for n in 1...1000 { delivery.submit(.desktopPointer, deliveryBody(n,token:1)) }
delivery.submit(.desktopPointer,deliveryBody(1001,token:1,action:1))
for n in 1002...2000 { delivery.submit(.desktopPointer,deliveryBody(n,token:1)) }
delivery.submit(.desktopKeyboard,Data([0]))
delivery.submit(.desktopPointer,deliveryBody(2001,token:1,action:2))
delivery.submit(.desktopControl,Data([1]))
delivery.submit(.desktopPointer,deliveryBody(2002,token:2))
check(delivery.pendingCount == 7, "blocked input consumer retains only current positions across callbacks")
release.signal(); deliveryQueue.sync {}
deliveryLock.lock(); let deliveredSnapshot = delivered, overflowSnapshot = overflows; deliveryLock.unlock()
check(deliveredSnapshot.map { $0.1 } == [deliveryBody(1000,token:1),deliveryBody(1001,token:1,action:1),deliveryBody(2000,token:1),Data([0]),deliveryBody(2001,token:1,action:2),Data([1]),deliveryBody(2002,token:2)] && overflowSnapshot == 0, "stalled capture skips old moves while preserving click, key, release and lease order")
let cancelQueue = DispatchQueue(label: "input-delivery-cancel")
let cancelBlocked = DispatchSemaphore(value: 0), cancelRelease = DispatchSemaphore(value: 0)
cancelQueue.async { cancelBlocked.signal(); _ = cancelRelease.wait(timeout: .now()+3) }
_ = cancelBlocked.wait(timeout: .now()+1)
var cancelledDelivery = 0
let cancelled = OrderedInputDelivery(queue: cancelQueue, receive: { _,_ in cancelledDelivery += 1 }, overflow: {})
cancelled.submit(.pointer,deliveryBody(1)); cancelled.cancel(); cancelled.submit(.pointer,deliveryBody(2))
cancelRelease.signal(); cancelQueue.sync {}
check(cancelledDelivery == 0 && cancelled.pendingCount == 0, "session cancellation discards queued and late input")
let floodQueue = DispatchQueue(label: "input-delivery-bound")
let floodBlocked = DispatchSemaphore(value: 0), floodRelease = DispatchSemaphore(value: 0)
floodQueue.async { floodBlocked.signal(); _ = floodRelease.wait(timeout: .now()+3) }
_ = floodBlocked.wait(timeout: .now()+1)
var floodDelivered = 0, floodReports = 0
let flood = OrderedInputDelivery(queue: floodQueue, limit: 4, receive: { _,_ in floodDelivered += 1 }, overflow: { floodReports += 1 })
for _ in 0..<100 { flood.submit(.keyboard,Data([0])) }
floodRelease.signal(); floodQueue.sync {}
check(floodDelivered == 0 && floodReports == 1 && flood.pendingCount == 0, "control overflow ends the session once without dropping a release into a live stream")
print("RESULT", failures, "failures")
exit(failures == 0 ? 0 : 1)
