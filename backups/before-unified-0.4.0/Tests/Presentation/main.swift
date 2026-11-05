import AppKit
import Network
setbuf(stdout,nil)
var failures = 0
func check(_ ok: Bool, _ name: String) { print(ok ? "PASS:" : "FAIL:",name); if !ok { failures += 1 } }
func pump(_ condition: () -> Bool, seconds: Double = 8) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while !condition(), Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
    return condition()
}
var pixel: CVPixelBuffer?
CVPixelBufferCreate(nil,1,1,kCVPixelFormatType_32BGRA,nil,&pixel)
var accepted = 0, skipped = 0, rendered = 0
let mailbox = LatestVideoPresenter { _ in rendered += 1; return true }
for _ in 0..<100 { mailbox.submit(pixel!) { result in
    if case .accepted = result { accepted += 1 }; if case .skipped = result { skipped += 1 }
} }
check(pump({ accepted == 1 }) && skipped == 99 && rendered == 1,"replaced frames complete as skipped, only the newest is accepted")
mailbox.submit(pixel!) { if case .skipped = $0 { skipped += 1 } }
mailbox.clear()
check(skipped == 100,"clearing a queued frame never reports an accepted image")
var unavailable = false
let blocked = LatestVideoPresenter { _ in false }
blocked.submit(pixel!) { if case .skipped = $0 { unavailable = true } }
check(pump({ unavailable }),"renderer backpressure is reported as skipped")
var failed = false
let broken = LatestVideoPresenter { _ in throw AireError("Synthetic presentation failure") }
broken.submit(pixel!) { if case .failed(let reason) = $0 { failed = reason.contains("Synthetic") } }
check(pump({ failed }),"renderer failure retains its explanation")
let q = DispatchQueue(label:"PresentationTests.server")
let key = try newPairingKey()
let listener = try NWListener(using:networkParameters(key:key),on:.any)
let engine = ReceiverEngine()
let template = try VideoFrame(Data(contentsOf:URL(fileURLWithPath:"build/CoreTests-sample.dat")))
var port: NWEndpoint.Port?, peer: Peer?
var callbacks: [(PresentationResult)->Void] = []
var reports: [UInt64] = [], acknowledgements = 0, modes = 0
engine.onPixel = { _,done in DispatchQueue.main.async { callbacks.append(done) } }
engine.onCursorMode = { _ in DispatchQueue.main.async { modes += 1 } }
listener.stateUpdateHandler = { if case .ready = $0 { DispatchQueue.main.async { port = listener.port } } }
listener.newConnectionHandler = { connection in
    let p = Peer(connection,queue:q);peer = p
    p.onReady = { p.send(.hello,Wire.hello(role:"sender")) }
    p.onPacket = { kind,data in
        if kind == .ack { DispatchQueue.main.async { acknowledgements += 1 } }
        if kind == .presented { var r = Reader(data); if let seq = try? r.u64() { DispatchQueue.main.async { reports.append(seq) } } }
    }
    p.start()
}
func frame(_ seq: UInt64) { q.async { peer?.send(.video,VideoFrame(sequence:seq,timestamp:monotonicNS(),sps:template.sps,pps:template.pps,avcc:template.avcc).serialize()) } }
listener.start(queue:q)
check(pump({ port != nil }),"presentation listener becomes available")
try engine.connect(endpoint:.hostPort(host:"127.0.0.1",port:port!),key:key,previouslyApproved:true)
check(pump({ engine.queue.sync { engine.phase == .preparing } }),"authenticated hello alone does not report a displayed image")
frame(1)
check(pump({ callbacks.count == 1 && acknowledgements == 1 }),"decode acknowledgement does not wait for the UI callback")
callbacks[0](.skipped)
RunLoop.current.run(until:Date().addingTimeInterval(0.1))
check(reports.isEmpty && engine.queue.sync { engine.phase == .preparing },"a skipped image cannot mark the connection active")
frame(2);check(pump({ callbacks.count == 2 }),"second frame reaches the presentation queue")
q.async { peer?.send(.cursorMode,Data([0])) }
check(pump({ modes == 1 }),"capture reconfiguration starts a new presentation epoch")
callbacks[1](.accepted)
RunLoop.current.run(until:Date().addingTimeInterval(0.1))
check(reports.isEmpty && engine.queue.sync { engine.phase == .preparing },"a late old-capture callback cannot confirm a new capture")
frame(3);check(pump({ callbacks.count == 3 }),"new capture reaches the presentation queue")
callbacks[2](.accepted)
check(pump({ reports == [3] && engine.queue.sync { engine.phase == .streaming } }),"first accepted image reports its sequence and activates the connection")
frame(4);check(pump({ callbacks.count == 4 }),"subsequent decoded frame reaches the presentation queue")
callbacks[3](.accepted)
RunLoop.current.run(until:Date().addingTimeInterval(0.1))
check(reports == [3],"one confirmation per capture avoids a new per-frame control packet")
frame(5);check(pump({ callbacks.count == 5 }),"last callback can remain pending during disconnection")
engine.stop();check(pump({ engine.queue.sync { engine.phase == .idle } }),"manual stop returns to disconnected state")
callbacks[4](.accepted)
RunLoop.current.run(until:Date().addingTimeInterval(0.1))
check(engine.queue.sync { engine.phase == .idle },"late callbacks cannot reactivate a stopped session")
listener.cancel();peer?.end();engine.stop()
print("RESULT",failures,"failures; synthetic presentation, no display capture or OS input posted")
exit(failures == 0 ? 0 : 1)
