import AppKit
setbuf(stdout, nil)
var failures = 0
func check(_ ok: Bool, _ text: String) { print(ok ? "PASS:" : "FAIL:", text); if !ok { failures += 1 } }
func pump(_ condition: () -> Bool, seconds: Double = 5) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while !condition() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
    return condition()
}
let sender = SenderEngine()
Capture.initialBeforeCompletion = true
sender.compatibilityEncoderEnabled = false
sender.screenPermission = { true }; sender.pointer.trusted = { false }; sender.keyboard.trusted = { false }
sender.pointer.post = { _ in check(false, "no OS pointer events") }; sender.keyboard.post = { _ in check(false, "no OS keyboard events") }
sender.dedicatedCursorEnabled = false; sender.videoFlightLimit = 2
let queue = DispatchQueue(label: "Pipeline.receiver"), decoder = H264Decoder()
var link: ConnectionLink?, peer: Peer?, sequences: [UInt64] = [], sizes: [Int] = [], ended = false
sender.onLink = { value in DispatchQueue.main.async { link = value } }
do {
    try sender.start(key: newPairingKey(), options: StreamOptions(extend: false, width: 640, height: 360, fps: 30, bitrate: 6_000_000))
    check(pump({ link != nil }), "source advertises")
    let connection = Peer(NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: link!.port)!, using: try networkParameters(key: link!.key)), queue: queue)
    peer = connection
    connection.onReady = { connection.send(.hello, Wire.hello(role: "receiver")) }
    connection.onEnd = { _ in DispatchQueue.main.async { ended = true } }
    decoder.onPixel = { pixel in DispatchQueue.main.async { sizes.append(CVPixelBufferGetWidth(pixel)) } }
    connection.onPacket = { kind, data in
        guard kind == .video else { return }
        do {
            let frame = try VideoFrame(data); try decoder.decode(frame)
            var ack = Data(); ack.u64(frame.sequence); ack.u64(frame.timestamp); ack.u64(0); connection.send(.ack, ack)
            DispatchQueue.main.async { sequences.append(frame.sequence) }
        } catch { DispatchQueue.main.async { check(false, "codec/protocol: \(error)") } }
    }
    connection.start()
    check(pump({ sequences.count >= 2 }), "one captured image starts Intel's bounded two-image pipeline")
    check(sequences.count == 2, "single captured image does not generate an unbounded warm-up loop")
    let before = sequences.count, started = Date()
    Capture.latest?.emit()
    check(pump({ sequences.count > before }, seconds: 1) && Date().timeIntervalSince(started) < 0.8, "last damaged image is delivered when capture becomes idle")
    Capture.latest?.emit()
    sender.update(options: StreamOptions(extend: false, width: 800, height: 450, fps: 30, bitrate: 12_000_000))
    check(pump({ sizes.contains(800) }), "resolution change retains its only image even when capture delivers it before start completes")
    sender.update(options: StreamOptions(extend: false, width: 800, height: 450, fps: 30, bitrate: 40_000_000))
    let prior = sequences.count; Capture.latest?.emit()
    check(pump({ sequences.count > prior }) && !ended, "quality changes preserve the active stream")
    check(zip(sequences, sequences.dropFirst()).allSatisfy { $0 < $1 }, "sequence numbers stay ordered across drain and reconfiguration")
} catch { check(false, "unexpected: \(error)") }
sender.stop(); peer?.end(); decoder.stop()
Capture.periodic = true
Capture.initialBeforeCompletion = false
let continuous = SenderEngine(), auxiliary = CursorChannel()
continuous.compatibilityEncoderEnabled = false
continuous.screenPermission = { true }; continuous.pointer.trusted = { false }; continuous.keyboard.trusted = { false }
continuous.pointer.post = { _ in check(false, "no OS pointer events") }; continuous.keyboard.post = { _ in check(false, "no OS keyboard events") }
var lateLink: ConnectionLink?, latePeer: Peer?, dependent = 0, lateReady = false
continuous.onLink = { value in DispatchQueue.main.async { lateLink = value } }
do {
    try continuous.start(key: newPairingKey(), options: StreamOptions(extend: false, width: 640, height: 360, fps: 30, bitrate: 6_000_000))
    check(pump({ lateLink != nil }), "continuous source advertises")
    let connection = Peer(NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: lateLink!.port)!, using: try networkParameters(key: lateLink!.key)), queue: queue)
    latePeer = connection
    connection.onReady = { connection.send(.hello, Wire.hello(role: "receiver")) }
    auxiliary.onReady = { DispatchQueue.main.async { lateReady = true } }
    connection.onPacket = { kind, data in
        do {
            if kind == .cursorOffer {
                let offer = try CursorOffer(data)
                queue.asyncAfter(deadline: .now()+0.4) { try? auxiliary.startClient(offer: offer, video: connection.connection, receive: { _ in }) }
            } else if kind == .video {
                let frame = try VideoFrame(data)
                var reader = Reader(frame.avcc), isDependent = false, remaining = frame.avcc.count
                while remaining > 0 { let size = Int(try reader.u32()); let bytes = try reader.bytes(size); remaining -= size+4; if bytes.first.map({ $0 & 31 == 1 }) == true { isDependent = true } }
                if isDependent { DispatchQueue.main.async { dependent += 1 } }
                // Keep at least one image awaiting its ACK when control becomes
                // ready: the former two-free-slots condition never enabled P frames.
                queue.asyncAfter(deadline: .now()+0.08) {
                    var ack = Data(); ack.u64(frame.sequence); ack.u64(frame.timestamp); ack.u64(0); connection.send(.ack, ack)
                }
            }
        } catch { DispatchQueue.main.async { check(false, "late control: \(error)") } }
    }
    connection.start()
    check(pump({ lateReady && dependent >= 10 }, seconds: 8), "late control handshake enables compression during continuous video with outstanding ACKs")
} catch { check(false, "late source: \(error)") }
continuous.stop(); latePeer?.end(); auxiliary.stop(); Capture.periodic = false
print("RESULT:", failures, "failures; synthetic capture, real Intel codec and TLS, no OS input")
exit(failures == 0 ? 0 : 1)
