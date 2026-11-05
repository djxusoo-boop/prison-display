import AppKit
setbuf(stdout, nil)
if CommandLine.arguments.contains("--virtual-display-helper") { exit(ADVirtualScreen.runHelper(CommandLine.arguments)) }
CGDisplayRegisterReconfigurationCallback({ _, _, _ in }, nil)
import Network
import CoreVideo

func pump(_ condition: () -> Bool, timeout: Double = 10) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { autoreleasepool { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) } }
    return condition()
}
var failures = 0
func check(_ value: Bool, _ name: String) { print(value ? "PASS:" : "FAIL:", name); if !value { failures += 1 } }
func displayIDs() -> [UInt32] {
    var count: UInt32 = 0; CGGetOnlineDisplayList(0, nil, &count)
    var ids = [UInt32](repeating: 0, count: Int(count)); CGGetOnlineDisplayList(count, &ids, &count); return ids
}
func tinyPixel(_ value: UInt8) -> CVPixelBuffer {
    var pixel: CVPixelBuffer?
    CVPixelBufferCreate(nil, 1, 1, kCVPixelFormatType_32BGRA, nil, &pixel)
    CVPixelBufferLockBaseAddress(pixel!, [])
    CVPixelBufferGetBaseAddress(pixel!)!.assumingMemoryBound(to: UInt8.self)[0] = value
    CVPixelBufferUnlockBaseAddress(pixel!, [])
    return pixel!
}
var renderedImages = 0
var lastRendered = 0
var presentationCompletions = 0
let mailbox = LatestVideoPresenter { pixel in
    renderedImages += 1
    CVPixelBufferLockBaseAddress(pixel, .readOnly)
    lastRendered = Int(CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)[0])
    CVPixelBufferUnlockBaseAddress(pixel, .readOnly); return true
}
for value in 1...100 { mailbox.submit(tinyPixel(UInt8(value))) { _ in presentationCompletions += 1 } }
check(pump({ presentationCompletions == 100 }) && renderedImages == 1 && lastRendered == 100, "busy interface presents only the latest decoded image")
mailbox.submit(tinyPixel(101)) { _ in presentationCompletions += 1 }
mailbox.clear()
mailbox.submit(tinyPixel(102)) { _ in presentationCompletions += 1 }
check(pump({ presentationCompletions == 102 }) && renderedImages == 2 && lastRendered == 102, "old scheduled presentation cannot overwrite a new connection")
let baseline = displayIDs()
let deniedSender = SenderEngine(); deniedSender.screenPermission = { false }
do { try deniedSender.start(key: newPairingKey(), options: StreamOptions(extend: false, width: 1280, height: 720, fps: 30, bitrate: 6_000_000)); check(false, "screen permission rejected before listener") } catch { check(String(describing: error).contains("pantalla"), "screen permission rejected before listener") }
let sender = SenderEngine(); sender.screenPermission = { true }
var senderPhases: [StreamPhase] = []
var confirmedImages = 0
var staleListenerHandler: ((NWListener.State) -> Void)?
sender.onListenerPrepared = { listener in if staleListenerHandler == nil { staleListenerHandler = listener.stateUpdateHandler } }
sender.onPhase = { phase in DispatchQueue.main.async { senderPhases.append(phase) } }
sender.onFirstImage = { DispatchQueue.main.async { confirmedImages += 1 } }
let decoder = H264Decoder()
let clientQueue = DispatchQueue(label: "PrisonDisplayTests.receiver", qos: .userInteractive)
var receivedSequence: UInt64 = 0
var client: Peer?
var error: String?
var stopped = false
var waitingForReconnect = false
var protectedFromOverload = false
var streamLink: ConnectionLink?
var cursorPositions: [PointerMessage] = []
var cursorModes: [Bool] = []
var desktopReplies: [DesktopControlMessage] = []
var inputEvents: [CGEvent] = []
sender.pointer.post = { event in DispatchQueue.main.async { inputEvents.append(event) } }
sender.keyboard.post = { event in DispatchQueue.main.async { inputEvents.append(event) } }
sender.pointer.trusted = { true }; sender.keyboard.trusted = { true }
sender.desktopPermission = { true }
func desktopInput(_ kind: Wire.Kind, _ body: Data, token: UInt64) {
    var data = Data(); data.u64(token); data.append(body); client?.send(kind, data)
}
var simulatedPoint = CGPoint(x: -100000, y: -100000)
sender.cursorLocation = { simulatedPoint }
var sequence: UInt64 = 0
var pixels = 0
var dimensions = (0, 0)
decoder.onPixel = { pixel in let size = (CVPixelBufferGetWidth(pixel), CVPixelBufferGetHeight(pixel)); DispatchQueue.main.async { pixels += 1; dimensions = size } }
sender.onStatus = { print("STATUS:", $0); if $0.hasPrefix("Conexión interrumpida") { waitingForReconnect = true }; if $0.contains("saturando el sistema de color") { protectedFromOverload = true } }
sender.onLink = { link in
    guard let link = link else { return }
    streamLink = link
    DispatchQueue.main.async {
        guard client == nil else { return }
        do {
            let peer = Peer(NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: link.port)!, using: try networkParameters(key: link.key)), queue: clientQueue)
            client = peer
            peer.onReady = { peer.send(.hello, Wire.hello(role: "receiver")) }
            peer.onPacket = { kind, data in
                do {
                    if kind == .desktopControl { let message = try DesktopControlMessage(data); DispatchQueue.main.async { desktopReplies.append(message) } }
                    if kind == .cursorMode { DispatchQueue.main.async { cursorModes.append(data == Data([1])) } }
                    if kind == .cursor { let message = try PointerMessage(Data(data.dropFirst(2))); DispatchQueue.main.async { cursorPositions.append(message) } }
                    if kind == .video {
                        let frame = try VideoFrame(data)
                        guard frame.sequence > receivedSequence else { throw AireError("Sequence restarted") }
                        receivedSequence = frame.sequence
                        DispatchQueue.main.async { sequence = frame.sequence }
                        try decoder.decode(frame)
                        var ack = Data(); ack.u64(frame.sequence); ack.u64(frame.timestamp); ack.u64(0)
                        // Delayed display acknowledgement makes changes happen with frames in flight.
                        clientQueue.asyncAfter(deadline: .now() + 0.075) { peer.send(.ack, ack); var report = Data(); report.u64(frame.sequence); peer.send(.presented, report) }
                    }
                } catch let e { DispatchQueue.main.async { error = "\(e)" } }
            }
            peer.onEnd = { reason in DispatchQueue.main.async { stopped = true; if error == nil { print("END:", reason) } } }
            peer.start()
        } catch let e { error = "\(e)" }
    }
}
do {
    try sender.start(key: newPairingKey(), options: StreamOptions(extend: true, width: 1280, height: 720, fps: 60, bitrate: 6_000_000))
    check(pump({ pixels >= 5 || error != nil }, timeout: 45) && error == nil && pixels >= 5, "initial synthetic stream through real sender and TLS")
    check(pump({ confirmedImages == 1 }) && senderPhases.contains(.preparing) && senderPhases.last == .streaming, "sender waits for the receiver presentation report before reporting a live image")
    check(sender.queue.sync { sender.streamActivity.isActive }, "authenticated sender holds a streaming activity")
    client?.send(.desktopControl, DesktopControlMessage(action: .begin, token: 1).serialize())
    check(pump({ desktopReplies.last?.action == .accepted }), "authenticated desktop control accepted on real TLS")
    let point = PointerMessage(action: .leftDown, x: 0.25, y: 0.5)
    desktopInput(.desktopPointer, point.serialize(), token: 1)
    desktopInput(.desktopKeyboard, KeyboardMessage(action: .down, keyCode: 0).serialize(), token: 1)
    check(pump({ inputEvents.count >= 2 }), "desktop mouse and keyboard received without posting")
    check(inputEvents.first?.location == point.point(in: CGDisplayBounds(CGMainDisplayID())), "desktop mouse targets physical MacBook display instead of virtual screen")
    let qualityHeartbeat = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in client?.send(.desktopControl, DesktopControlMessage(action: .heartbeat, token: 1).serialize()) }
    let beforeQuality = pixels, modesBeforeQuality = cursorModes.count
    let frameBeforeQuality = sequence
    sender.update(options: StreamOptions(extend: true, width: 1280, height: 720, fps: 60, bitrate: 40_000_000))
    check(pump({ pixels >= beforeQuality + 4 }) && error == nil && !stopped, "quality-only change keeps the live video connected")
    check(cursorModes.count == modesBeforeQuality && sequence > frameBeforeQuality, "quality-only change retains capture and sequence")
    let inputsBeforeQuality = inputEvents.count
    desktopInput(.desktopPointer, PointerMessage(action: .move, x: 0.3, y: 0.4).serialize(), token: 1)
    check(pump({ inputEvents.count > inputsBeforeQuality }), "quality-only change retains desktop-control lease")
    qualityHeartbeat.invalidate()
    client?.send(.desktopControl, DesktopControlMessage(action: .end, token: 1).serialize())
    check(pump({ inputEvents.contains { $0.type == .leftMouseUp } && inputEvents.contains { $0.type == .keyUp } }), "lease end releases held mouse and key")
    let afterEnd = inputEvents.count
    desktopInput(.desktopPointer, point.serialize(), token: 1)
    desktopInput(.desktopKeyboard, KeyboardMessage(action: .down,keyCode: 0).serialize(),token: 1)
    _ = pump({ false }, timeout: 0.2)
    check(inputEvents.count == afterEnd, "late desktop input discarded after returning to iMac")
    client?.send(.desktopControl, DesktopControlMessage(action: .begin, token: 2).serialize())
    check(pump({ desktopReplies.last?.token == 2 && desktopReplies.last?.action == .accepted }), "second lease starts independently")
    client?.send(.desktopControl, DesktopControlMessage(action: .end, token: 1).serialize())
    desktopInput(.desktopPointer, point.serialize(),token: 2)
    check(pump({ inputEvents.count > afterEnd }), "old end cannot cancel current lease")
    client?.send(.pointer, point.serialize())
    let duringLease = inputEvents.count
    _ = pump({ false },timeout:0.2)
    check(inputEvents.count == duringLease, "ordinary viewer input cannot leak into desktop lease")
    check(pump({ desktopReplies.last?.token == 2 && desktopReplies.last?.action == .rejected },timeout:4), "sender expires missing heartbeat independently")
    check(inputEvents.last?.type == .leftMouseUp, "sender expiry releases held remote click")
    sender.queue.sync { sender.desktopPermission = { false } }
    client?.send(.desktopControl, DesktopControlMessage(action: .begin,token: 3).serialize())
    check(pump({ desktopReplies.last?.token == 3 && desktopReplies.last?.action == .rejected }), "desktop control denied without sender accessibility")
    sender.queue.sync { sender.desktopPermission = { true } }
    var virtualID = displayIDs().first { !baseline.contains($0) }
    let recoveryID = virtualID; let beforeRecovery = pixels
    Capture.latest?.onRecoverableError?("Synthetic missing source")
    check(pump({ pixels > beforeRecovery + 8 }) && error == nil && !stopped, "temporary capture source loss recovers without ending TLS")
    check(recoveryID != nil && displayIDs().contains(recoveryID!), "capture recovery preserves virtual display")
    for (width, height, fps, bitrate) in [(1920, 1080, 30, 12_000_000), (2560, 1440, 60, 20_000_000), (1280, 720, 60, 6_000_000)] {
        let previousCount = pixels
        sender.update(options: StreamOptions(extend: true, width: width, height: height, fps: fps, bitrate: bitrate))
        check(pump({ (dimensions == (width, height) && pixels >= previousCount + 6) || error != nil }) && error == nil && !stopped, "live resolution/FPS/bitrate change \(width)x\(height), connection retained")
        let oldID = virtualID
        virtualID = displayIDs().first { !baseline.contains($0) }
        print("DISPLAY", virtualID as Any, "ACTUAL", virtualID.map { CGDisplayPixelsWide($0) } as Any, virtualID.map { CGDisplayPixelsHigh($0) } as Any)
        check(virtualID != nil && virtualID.map { CGDisplayPixelsWide($0) == width && CGDisplayPixelsHigh($0) == height } == true, "virtual display uses selected resolution")
        check(oldID == virtualID || oldID.map { !displayIDs().contains($0) } == true, "old resolution display removed")
    }
    check(cursorModes.first == false, "fast cursor is default")
    let preservedID = virtualID
    let qualityCount = pixels
    sender.update(options: StreamOptions(extend: true, width: 1280, height: 720, fps: 30, bitrate: 20_000_000))
    check(pump({ pixels >= qualityCount + 6 }) && error == nil && !stopped, "FPS and quality update while connected")
    check(preservedID != nil && displayIDs().contains(preservedID!), "FPS and quality preserve virtual screen")
    let previousCount = pixels
    sender.update(options: StreamOptions(extend: false, width: 1280, height: 720, fps: 30, bitrate: 12_000_000))
    check(pump({ pixels >= previousCount + 6 || error != nil }) && error == nil && !stopped, "switch to mirroring retains TLS")
    check(pump({ virtualID.map { !displayIDs().contains($0) } ?? false }), "switch to mirroring removes virtual display")
    let beforeNative = pixels
    sender.update(options: StreamOptions(extend: false, width: 1280, height: 720, fps: 30, bitrate: 12_000_000, nativeCursor: true))
    check(pump({ cursorModes.last == true && pixels > beforeNative + 5 }), "original cursor mode changes during active stream")
    let beforeRapid = pixels
    sender.update(options: StreamOptions(extend: true, width: 1920, height: 1080, fps: 60, bitrate: 20_000_000))
    sender.update(options: StreamOptions(extend: true, width: 1280, height: 720, fps: 30, bitrate: 6_000_000))
    check(pump({ dimensions == (1280, 720) && pixels >= beforeRapid + 8 }) && error == nil && !stopped, "rapid changes converge and preserve frame order")
    if let id = displayIDs().first(where: { !baseline.contains($0) }) {
        var config: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&config)
        let leftEdge = baseline.map { CGDisplayBounds($0).minX }.min() ?? 0
        let expected = CGPoint(x: leftEdge - 1280, y: 40)
        CGConfigureDisplayOrigin(config, id, Int32(expected.x), Int32(expected.y))
        CGCompleteDisplayConfiguration(config, .forSession)
        let arranged = pump({ CGDisplayBounds(id).origin == expected })
        if !arranged { print("ARRANGE expected", expected, "actual", CGDisplayBounds(id), "baseline", baseline.map { CGDisplayBounds($0) }) }
        check(arranged, "virtual display arrangement changes")
        simulatedPoint = CGPoint(x: expected.x + 320, y: expected.y + 180)
        check(pump({ cursorPositions.last?.x == 0.25 && cursorPositions.last?.y == 0.25 }), "cursor samples the new display origin after rearrangement")
        let link = streamLink!
        let beforeCut = pixels
        client?.end("Test network cut")
        check(pump({ stopped && waitingForReconnect }), "stream cut reaches sender")
        check(pump({ senderPhases.last == .reconnecting }), "network cut clears live-image badge while keeping automatic reconnection available")
        check(!sender.queue.sync { sender.streamActivity.isActive }, "waiting for reconnection releases sender activity")
        check(pump({ displayIDs().contains(id) && CGDisplayBounds(id).origin == expected }), "cut preserves virtual display and arrangement")
        let availability = NWBrowser(for: .bonjour(type: PairingServer.service, domain: nil), using: discoveryParameters())
        var discoverableAgain = false
        availability.browseResultsChangedHandler = { results, _ in
            discoverableAgain = results.contains { result in
                if case .service(let name, _, _, _) = result.endpoint { return name == (Host.current().localizedName ?? "MacBook") }
                return false
            }
        }
        availability.start(queue: .main)
        check(pump({ discoverableAgain }), "sender advertises fresh pairing again after a cut")
        availability.cancel()
        client = nil; stopped = false
        sender.onLink?(link)
        check(pump({ pixels >= beforeCut + 6 || error != nil }) && error == nil && !stopped, "sender accepts authenticated reconnection and resumes frames")
        check(sender.queue.sync { sender.streamActivity.isActive }, "reconnection reacquires sender activity")
        check(displayIDs().contains(id) && CGDisplayBounds(id).origin == expected, "reconnection preserves display identity and placement")
    } else { check(false, "virtual display available for reconnect test") }
    sender.stop()
    check(pump({ stopped }), "stop after reconfiguration closes connection")
    check(pump({ senderPhases.last == .idle }), "manual stop removes the live connection state")
    check(!sender.queue.sync { sender.streamActivity.isActive }, "stop releases sender activity")
    let restored = pump({ displayIDs().sorted() == baseline.sorted() })
    if !restored { print("BASELINE", baseline, "AFTER STOP", displayIDs()) }
    check(restored, "stop restores original displays")
    // Simulate persistent system load and a missing stopCapture callback. The
    // emergency path must still disconnect and retire only our virtual display.
    client?.onPacket = nil; decoder.stop()
    client = nil; stopped = false; receivedSequence = 0; sequence = 0
    let beforeProtection = pixels
    sender.graphicsLoadReader = { 100 }
    try sender.start(key: newPairingKey(), options: StreamOptions(extend: true, width: 1280, height: 720, fps: 30, bitrate: 6_000_000))
    check(pump({ pixels > beforeProtection + 3 || error != nil }, timeout: 15) && error == nil, "protection test begins with a real encrypted stream")
    let beforeStale = pixels
    sender.queue.sync { staleListenerHandler?(.failed(.posix(.ENETDOWN))) }
    check(pump({ pixels >= beforeStale + 3 }) && sender.queue.sync { sender.streamActivity.isActive }, "late failure from a retired listener cannot stop the new connection")
    Capture.stopNeverResponds = true
    let inputBlocked = DispatchSemaphore(value: 0), unblockInput = DispatchSemaphore(value: 0)
    sender.queue.async { inputBlocked.signal(); _ = unblockInput.wait(timeout: .now()+12) }
    _ = inputBlocked.wait(timeout: .now()+1)
    check(pump({ displayIDs().sorted() == baseline.sorted() }, timeout: 8), "protection retires its display independently of a blocked input queue")
    unblockInput.signal()
    check(pump({ protectedFromOverload && stopped }, timeout: 10), "persistent colour overload pauses extension and reports the reason")
    check(pump({ displayIDs().sorted() == baseline.sorted() }, timeout: 6), "emergency retirement removes virtual screen even without capture stop reply")
    Capture.stopNeverResponds = false
} catch let e { error = "\(e)"; failures += 1 }
if let error = error { print("ERROR:", error) }
decoder.stop(); client?.end(); sender.stop()
let exitingSender = SenderEngine()
exitingSender.pointer.trusted = { false }; exitingSender.keyboard.trusted = { false }
let occupied = DispatchSemaphore(value: 0), releaseQueue = DispatchSemaphore(value: 0)
exitingSender.queue.async { occupied.signal(); releaseQueue.wait() }
_ = occupied.wait(timeout: .now()+1)
let exitStart = Date()
exitingSender.releasePointerBeforeExit()
check(Date().timeIntervalSince(exitStart) < 0.75, "quit cannot wait indefinitely on a blocked input queue")
releaseQueue.signal()
print("RESULT:", failures, "failures; synthetic capture, physical screen capture still needs GUI verification")
exit(failures == 0 ? 0 : 1)
