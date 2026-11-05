import AppKit
import Network
setbuf(stdout,nil)
var failures = 0
func check(_ ok: Bool, _ text: String) { print(ok ? "PASS:" : "FAIL:", text); if !ok { failures += 1 } }
func pump(_ condition: () -> Bool, seconds: Double = 8) -> Bool {
    let until = Date().addingTimeInterval(seconds)
    while !condition() && Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
    return condition()
}
let sender = SenderEngine(); sender.screenPermission = { true }
sender.pointer.trusted = { false }; sender.keyboard.trusted = { false }
sender.pointer.post = { _ in check(false,"no pointer may be posted") }; sender.keyboard.post = { _ in check(false,"no key may be posted") }
let q = DispatchQueue(label:"TemporaryCapture.client"), decoder = H264Decoder()
var link: ConnectionLink?, client: Peer?, frames = 0, failuresOnWire = 0, ended = false
var phases: [StreamPhase] = []
var confirmPresentation = false
sender.onLink = { value in DispatchQueue.main.async { if let value = value { link = value } } }
sender.onPhase = { value in DispatchQueue.main.async { phases.append(value) } }
decoder.onPixel = { _ in DispatchQueue.main.async { frames += 1 } }
func connect() throws {
    let saved = link!
    let p = Peer(NWConnection(host:"127.0.0.1", port:NWEndpoint.Port(rawValue:saved.port)!, using:try networkParameters(key:saved.key)), queue:q)
    client = p; ended = false
    p.onReady = { p.send(.hello, Wire.hello(role:"receiver")) }
    p.onEnd = { _ in DispatchQueue.main.async { ended = true } }
    p.onPacket = { kind, data in
        do {
            if kind == .failure { DispatchQueue.main.async { failuresOnWire += 1 } }
            if kind == .video {
                let frame = try VideoFrame(data); try decoder.decode(frame)
                var ack = Data(); ack.u64(frame.sequence); ack.u64(frame.timestamp); ack.u64(0); p.send(.ack,ack); if confirmPresentation { var report = Data(); report.u64(frame.sequence); p.send(.presented,report) }
            }
        } catch { DispatchQueue.main.async { check(false,"decode or protocol: \(error)") } }
    }
    p.start()
}
do {
    Capture.nextStartTransient = true
    try sender.start(key:newPairingKey(), options:StreamOptions(extend:false,width:640,height:360,fps:30,bitrate:6_000_000))
    check(pump({ link != nil }),"sender advertises before temporary capture failure")
    try connect()
    check(pump({ ended && phases.last == .reconnecting }),"temporary unavailable capture closes only the current stream")
    check(failuresOnWire == 0 && frames == 0,"temporary capture loss does not send a permanent permission failure")
    check(!sender.queue.sync { sender.streamActivity.isActive },"waiting for a screen releases the streaming activity")
    decoder.stop()
    try connect()
    check(pump({ frames >= 3 && phases.last == .preparing }),"decoded ACKs alone keep the source waiting for its viewer")
    q.sync { confirmPresentation = true }
    check(pump({ phases.last == .streaming }),"same authenticated link resumes after the viewer accepts an image")
    check(sender.queue.sync { sender.streamActivity.isActive },"recovered capture reacquires its streaming activity")
    var impossible = Data(); impossible.u64(UInt64.max)
    client?.send(.presented,impossible)
    check(pump({ ended && phases.last == .reconnecting }),"a future presentation sequence cannot confirm or keep the session active")
    decoder.stop(); let beforeReconnect = frames
    try connect()
    check(pump({ frames > beforeReconnect + 2 && phases.last == .streaming }),"a valid session can recover after an invalid presentation report")
    client?.send(.presented,Data([1]))
    check(pump({ ended && phases.last == .reconnecting }),"a truncated presentation report is rejected safely")
    decoder.stop(); let beforeFinal = frames
    try connect()
    check(pump({ frames > beforeFinal + 2 && phases.last == .streaming }),"malformed report cannot contaminate a subsequent connection")
    sender.stop(); check(pump({ ended && phases.last == .idle }),"manual stop still cancels the recovered stream")
    let oldLink = link!.url
    decoder.stop(); Capture.nextStartDenied = true
    try sender.start(key:newPairingKey(),options:StreamOptions(extend:false,width:640,height:360,fps:30,bitrate:6_000_000))
    check(pump({ link?.url != oldLink }),"new source starts independently of the retired connection")
    try connect()
    check(pump({ ended && phases.last == .failed }) && failuresOnWire == 1,"denied permission remains a definitive error instead of an automatic retry")
} catch { check(false,"unexpected \(error)") }
decoder.stop(); client?.end(); sender.stop()
print("RESULT",failures,"failures; synthetic capture and virtual-display stub, no OS input posted")
exit(failures == 0 ? 0 : 1)
