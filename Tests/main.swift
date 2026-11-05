import Foundation
#if !LEGACY
import Network
#endif
import CoreVideo
import CoreMedia
import CoreImage

var failures = 0
func check(_ condition: Bool, _ name: String) {
    if condition { print("PASS: \(name)") } else { print("FAIL: \(name)"); failures += 1 }
}
func rejects(_ name: String, _ body: () throws -> Void) {
    do { try body(); check(false, name) } catch { check(true, name) }
}
func pump(until: () -> Bool, seconds: Double = 10) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while !until() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    return until()
}
func pixel(_ width: Int, _ height: Int, value: UInt8) throws -> CVPixelBuffer {
    var p: CVPixelBuffer?
    let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
    guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs, &p) == noErr, let p = p else { throw AireError("pixel allocation") }
    CVPixelBufferLockBaseAddress(p, [])
    let stride = CVPixelBufferGetBytesPerRow(p); let ptr = CVPixelBufferGetBaseAddress(p)!.assumingMemoryBound(to: UInt8.self)
    for y in 0..<height { for x in 0..<width { let i = y * stride + x * 4; ptr[i] = value; ptr[i + 1] = value; ptr[i + 2] = value; ptr[i + 3] = 255 } }
    CVPixelBufferUnlockBaseAddress(p, []); return p
}
do {
    var ints = Data(); ints.u16(0xABCD); ints.u32(0xABCDEF01); ints.u64(UInt64.max)
    var reader = Reader(ints); check(try reader.u16() == 0xABCD, "UInt16 big-endian"); check(try reader.u32() == 0xABCDEF01, "UInt32 big-endian"); check(try reader.u64() == UInt64.max, "UInt64 big-endian")
    var parser = PacketParser(); let packet = Wire.packet(.hello, Wire.hello(role: "sender")); var decoded: [(Wire.Kind, Data)] = []
    for byte in packet { decoded += try parser.feed(Data([byte])) }
    check(decoded.count == 1 && decoded[0].0 == .hello, "fragmented packet byte by byte")
    check(try Wire.checkHello(decoded[0].1, expected: "sender") == AppVersion.current, "version handshake")
    check(try parser.feed(packet + packet).count == 2, "coalesced packets")
    rejects("zero packet length") { var p = PacketParser(); _ = try p.feed(Data([0, 0, 0, 0])) }
    rejects("oversized packet") { var p = PacketParser(); _ = try p.feed(Data([255, 255, 255, 255])) }
    rejects("unknown packet") { var p = PacketParser(); _ = try p.feed(Data([0, 0, 0, 1, 99])) }
    rejects("short frame") { _ = try VideoFrame(Data([1, 2, 3])) }
    rejects("wrong role") { _ = try Wire.checkHello(Wire.hello(role: "receiver"), expected: "sender") }
    rejects("wrong protocol") { _ = try Wire.checkHello(Data([0, 99]) + Data("sender|0.1.0".utf8), expected: "sender") }
    var wrongVersion = Data(); wrongVersion.u16(Wire.revision); wrongVersion.append(Data("sender|9.9.9|TWFj".utf8))
    rejects("wrong app version") { _ = try Wire.checkHello(wrongVersion, expected: "sender") }
    let namedHello = Wire.hello(role: "receiver", name: "MacBook Pro · José | 2014")
    check(try Wire.peerName(namedHello) == "MacBook Pro · José | 2014", "authenticated hello preserves Unicode names and delimiters")
    check(try Wire.checkHello(namedHello, expected: "receiver") == AppVersion.current, "named hello validates version and role")
    for malformed in ["sender|\(AppVersion.current)|***", "sender|\(AppVersion.current)|", "sender|\(AppVersion.current)|" + Data("Mac\nforged status".utf8).base64EncodedString()] {
        var data = Data(); data.u16(Wire.revision); data.append(Data(malformed.utf8))
        rejects("invalid remote name") { _ = try Wire.checkHello(data, expected: "sender") }
    }
    check(try Wire.peerName(Wire.hello(role: "sender", name: String(repeating: "a", count: 1000))) == "Este Mac", "oversized local name is bounded")
    let key = try newPairingKey(); check(try normalizedKey(key.lowercased()) == key, "random pairing key normalization")
    rejects("invalid pairing key") { _ = try normalizedKey("000000") }
    var latest = LatestFrame<Int>()
    for image in 1...100 { latest.offer(image) }
    check(latest.take() == 100 && latest.take() == nil, "backpressure retains only the most recent capture")
    latest.offer(101); latest.clear()
    check(latest.take() == nil, "disconnect clears pending capture")
    let deliveryQueue = DispatchQueue(label: "LatestDelivery.blocked"), releaseDelivery = DispatchSemaphore(value: 0)
    var deliveredValues: [Int] = []
    deliveryQueue.async { releaseDelivery.wait() }
    let delivery = LatestDelivery<Int>(queue: deliveryQueue) { deliveredValues.append($0) }
    DispatchQueue.concurrentPerform(iterations: 10000) { delivery.offer($0) }
    delivery.offer(10001); releaseDelivery.signal(); deliveryQueue.sync {}
    check(deliveredValues == [10001], "concurrent capture producers queue only the latest delivery")
    delivery.offer(10002); deliveryQueue.sync {}
    check(deliveredValues == [10001,10002], "delivery re-arms after a consumed image")
    let releaseCancelled = DispatchSemaphore(value: 0)
    deliveryQueue.async { releaseCancelled.wait() }
    delivery.offer(10003); delivery.cancel(); releaseCancelled.signal(); deliveryQueue.sync {}
    check(deliveredValues == [10001,10002], "retiring capture clears a delivery already queued")
    delivery.offer(10004); deliveryQueue.sync {}
    check(deliveredValues == [10001,10002], "retired capture cannot resume from a late callback")
    var quality = AdaptiveQuality(ceiling: 20_000_000)
    check(quality.bitrate == 20_000_000, "explicit high quality starts at its selected budget")
    for tick in 0...60 {
        let rtt = tick % 60 >= 57 ? 300.0 : 20.0
        _ = quality.observe(roundTripMS: rtt, now: UInt64(tick) * 16_666_667)
    }
    check(quality.bitrate == 20_000_000, "brief stalls do not reduce image quality")
    var jitter = AdaptiveQuality(ceiling: 40_000_000)
    for second in 0...5 {
        for frame in 0..<60 {
            let rtt = frame % 10 < 3 ? 150.0 : 25.0
            _ = jitter.observe(roundTripMS: rtt, now: UInt64(second) * 1_000_000_000 + UInt64(frame) * 16_666_667)
        }
    }
    check(jitter.bitrate < 40_000_000, "sustained Wi-Fi jitter lowers video load even with a healthy median")
    for tick in 61...300 { _ = quality.observe(roundTripMS: 120, now: UInt64(tick) * 16_666_667) }
    check(quality.bitrate == 18_000_000, "sustained moderate congestion reduces quality gradually")
    for tick in 6...100 {
        for frame in 0..<60 { _ = quality.observe(roundTripMS: 150, now: UInt64(tick) * 1_000_000_000 + UInt64(frame) * 16_666_667) }
    }
    check(quality.bitrate == 1_500_000, "quality reduction has a lower bound")
    for tick in 101...220 { for frame in 0..<60 { _ = quality.observe(roundTripMS: 20, now: UInt64(tick) * 1_000_000_000 + UInt64(frame) * 16_666_667) } }
    check(quality.bitrate <= 20_000_000 && quality.bitrate > 1_500_000, "stable network slowly recovers quality without exceeding user ceiling")
    var severe = AdaptiveQuality(ceiling: 12_000_000)
    for tick in 0...120 { _ = severe.observe(roundTripMS: 350, now: UInt64(tick) * 16_666_667) }
    check(severe.bitrate == 4_500_000, "persistent severe congestion still triggers faster backoff")
    var limitedQuality = AdaptiveQuality(ceiling: 6_000_000)
    for tick in 1...60 { for frame in 0..<30 { _ = limitedQuality.observe(roundTripMS: 10, now: UInt64(tick) * 1_000_000_000 + UInt64(frame) * 33_333_333) } }
    check(limitedQuality.bitrate == 6_000_000, "Wi-Fi slow profile remains within its ceiling")
    let beforeInvalid = limitedQuality.bitrate
    _ = limitedQuality.observe(roundTripMS: .nan, now: 61_000_000_000)
    _ = limitedQuality.observe(roundTripMS: -1, now: 61_000_000_000)
    _ = limitedQuality.observe(roundTripMS: 350, now: 1)
    check(limitedQuality.bitrate == beforeInvalid, "invalid samples and backwards clocks do not change quality")
    var ample = AdaptiveQuality(ceiling: 40_000_000)
    for tick in 0...30 { for frame in 0..<30 { _ = ample.observe(roundTripMS: 25, now: UInt64(tick)*1_000_000_000 + UInt64(frame)*33_333_333) } }
    check(ample.bitrate == 40_000_000, "healthy link reaches 40Mbps in under 31 seconds")
    ample.reconfigure(ceiling: 6_000_000)
    check(ample.bitrate == 6_000_000, "live ceiling reduction clamps the encoder immediately")
    ample.reconfigure(ceiling: 40_000_000)
    check(ample.bitrate == 6_000_000, "live ceiling increase preserves settled rate without a burst")
    var cautious = AdaptiveQuality(ceiling: 40_000_000)
    for tick in 0...15 { for frame in 0..<30 { _ = cautious.observe(roundTripMS: frame < 20 ? 20 : 110, now: UInt64(tick)*1_000_000_000 + UInt64(frame)*33_333_333) } }
    check(cautious.bitrate == 40_000_000, "frequent stalls prevent quality growth despite a good median")
    var cooldown = AdaptiveQuality(ceiling: 40_000_000)
    for tick in 0...6 { for frame in 0..<30 { _ = cooldown.observe(roundTripMS: 120, now: UInt64(tick)*1_000_000_000 + UInt64(frame)*33_333_333) } }
    let backedOff = cooldown.bitrate
    for tick in 7...19 { for frame in 0..<30 { _ = cooldown.observe(roundTripMS: 20, now: UInt64(tick)*1_000_000_000 + UInt64(frame)*33_333_333) } }
    check(cooldown.bitrate == backedOff, "congestion cooldown prevents rapid quality oscillation")
    var window = VideoWindow()
    for seq in 1...3 { try window.sent(sequence: UInt64(seq), timestamp: UInt64(seq * 10)) }
    check(!window.hasRoom, "three in-flight frames bound the queue")
    rejects("fourth frame rejected") { try window.sent(sequence: 4, timestamp: 40) }
    rejects("forged timestamp rejected") { try window.acknowledge(sequence: 1, timestamp: 11) }
    check(!window.hasRoom, "invalid acknowledgement does not release credit")
    try window.acknowledge(sequence: 1, timestamp: 10)
    check(window.hasRoom, "acknowledgement permits next frame while two remain in transit")
    rejects("duplicate acknowledgement rejected") { try window.acknowledge(sequence: 1, timestamp: 10) }
    try window.sent(sequence: 4, timestamp: 40)
    window.reset()
    check(window.hasRoom, "disconnect resets flow window")
    var interactive = VideoWindow(limit: 1)
    try interactive.sent(sequence: 10, timestamp: 100)
    check(!interactive.hasRoom, "interactive stream waits for the current image before encoding more")
    rejects("interactive stream cannot build a backlog") { try interactive.sent(sequence: 11, timestamp: 110) }
    rejects("forged interactive acknowledgement rejected") { try interactive.acknowledge(sequence: 10, timestamp: 99) }
    check(!interactive.hasRoom, "forged acknowledgement cannot release the interactive window")
    try interactive.acknowledge(sequence: 10, timestamp: 100)
    check(interactive.hasRoom, "valid acknowledgement permits the latest image")
    interactive.reset(); try interactive.sent(sequence: 12, timestamp: 120)
    check(!interactive.hasRoom, "reconnection preserves the one-image limit")
    interactive.setLimit(2)
    check(interactive.hasRoom, "independent input permits a second image without forgetting the first")
    try interactive.sent(sequence: 13, timestamp: 130)
    interactive.setLimit(1)
    check(!interactive.hasRoom, "failed auxiliary channel drains existing images before shrinking the window")
    try interactive.acknowledge(sequence: 12, timestamp: 120)
    check(!interactive.hasRoom, "shrinking window retains the remaining acknowledgement barrier")
    try interactive.acknowledge(sequence: 13, timestamp: 130)
    check(interactive.isEmpty && interactive.hasRoom, "all old images acknowledged before the fallback window resumes")
    var timed = VideoWindow(), codecQuality = AdaptiveQuality(ceiling: 40_000_000)
    for index in 0..<360 {
        let captured = UInt64(index)*33_333_333
        let handed = captured+300_000_000
        try timed.sent(sequence: UInt64(index+1), timestamp: captured, handedAt: handed)
        let networkTime = try timed.acknowledge(sequence: UInt64(index+1), timestamp: captured, now: handed+20_000_000)
        _ = codecQuality.observe(roundTripMS: Double(networkTime)/1e6, now: handed+20_000_000)
    }
    check(codecQuality.bitrate == 40_000_000, "a 300ms local codec delay does not degrade quality on a healthy 20ms transport")
    try timed.sent(sequence: 361, timestamp: 1, handedAt: 300)
    rejects("backwards transport clock rejected without releasing its frame") { try timed.acknowledge(sequence: 361, timestamp: 1, now: 299) }
    check(!timed.isEmpty, "invalid transport timing retains its acknowledgement barrier")
    check(try timed.acknowledge(sequence: 361, timestamp: 1, now: 320) == 20, "valid timing excludes the local encoding interval")
    let decoder = H264Decoder(); var decodedPixels = 0; var gray: Double = 0
    decoder.onPixel = { pixel in
        decodedPixels += 1
        if decodedPixels == 60 { print("PIXEL FORMAT:", CVPixelBufferGetPixelFormatType(pixel), "planar", CVPixelBufferIsPlanar(pixel), "stride", CVPixelBufferGetBytesPerRow(pixel)) }
        CVPixelBufferLockBaseAddress(pixel, .readOnly)
        gray = Double(CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)[0]); CVPixelBufferUnlockBaseAddress(pixel, .readOnly)
        if decodedPixels == 60 {
            var rendered = [UInt8](repeating: 0, count: 4)
            let context = CIContext()
            context.render(CIImage(cvPixelBuffer: pixel), toBitmap: &rendered, rowBytes: 4, bounds: CGRect(x: 640, y: 360, width: 1, height: 1), format: .BGRA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            print("GPU PIXEL", rendered)
        }
    }
    let encoder = try H264Encoder(width: 1280, height: 720, fps: 60, bitrate: 6_000_000)
    var encoded: [Data] = []; var videoError: String?
    encoder.onFrame = { encoded.append($0) }; encoder.onError = { videoError = $0 }
    let started = monotonicNS()
    for index in 0..<60 {
        let count = encoded.count; encoder.encode(try pixel(1280, 720, value: UInt8(40 + index)))
        check(pump(until: { encoded.count > count || videoError != nil }), "encoder output \(index + 1)")
        if let error = videoError { throw AireError(error) }
        guard encoded.count > count, let output = encoded.last else { throw AireError("Encoder timed out without output for frame \(index + 1)") }
        let frame = try VideoFrame(output); try decoder.decode(frame)
        check(frame.sequence == UInt64(index + 1), "sequence \(index + 1)")
    }
    check(decodedPixels == 60, "60 frames decoded without loss")
    print("PIXEL: decoded gray=\(gray), expected=99")
    check(abs(gray - 99) < 10, "decoded pixel content matches generated image")
    print("VIDEO ENCODER: hardware=\(encoder.hardware) (software fallback remains supported when macOS reserves it)")
    check(decoder.hardware, "M4 hardware decoder")
    print("VIDEO: 60 x 720p in \(Double(monotonicNS() - started) / 1e6) ms (includes test image generation; not Wi-Fi latency)")
    let compatibleEncoder = try H264Encoder(width: 640, height: 360, fps: 30, bitrate: 2_000_000, compatibilityLowLatency: true)
    var compatiblePacket: Data?; var compatibleError: String?
    compatibleEncoder.onFrame = { compatiblePacket = $0 }; compatibleEncoder.onError = { compatibleError = $0 }
    compatibleEncoder.encode(try pixel(640, 360, value: 80))
    compatibleEncoder.drain()
    check(pump(until: { compatiblePacket != nil || compatibleError != nil }) && compatibleError == nil, "software compatibility encoder creates without RTVC-only options")
    if let packet = compatiblePacket {
        try decoder.decode(VideoFrame(packet))
        check(!compatibleEncoder.hardware, "software compatibility encoder reports its actual mode")
    }
    compatibleEncoder.stop()
    var vectors = Data()
    for (index, packet) in encoded.enumerated() {
        vectors.u32(UInt32(packet.count)); vectors.u16(1280); vectors.u16(720); vectors.append(UInt8(40 + index)); vectors.append(packet)
    }
    try vectors.write(to: URL(fileURLWithPath: CommandLine.arguments[0] + "-vectors.dat"))
    encoder.stop(); decoder.stop()
    for (width, height, fps, bitrate) in [(1920, 1080, 60, 12_000_000), (2560, 1440, 30, 20_000_000)] {
        let e = try H264Encoder(width: width, height: height, fps: fps, bitrate: bitrate)
        let d = H264Decoder(); var packets: [Data] = []; var count = 0; var dimensionsOK = true; var error: String?
        e.onFrame = { packets.append($0) }; e.onError = { error = $0 }
        d.onPixel = { p in count += 1; dimensionsOK = dimensionsOK && CVPixelBufferGetWidth(p) == width && CVPixelBufferGetHeight(p) == height }
        for index in 0..<10 {
            e.encode(try pixel(width, height, value: UInt8(100 + index)))
            guard pump(until: { packets.count == index + 1 || error != nil }), error == nil else { throw AireError(error ?? "Video timeout") }
            try d.decode(VideoFrame(packets[index]))
        }
        check(count == 10 && dimensionsOK, "\(width)x\(height) / \(fps) FPS preset roundtrip and dimensions")
        e.stop(); d.stop()
    }
    let changingDecoder = H264Decoder()
    var continuedSequence: UInt64 = 100
    var changedImages = 0
    changingDecoder.onPixel = { _ in changedImages += 1 }
    for (width, height, fps, bitrate) in [(1280, 720, 30, 6_000_000), (1920, 1080, 60, 12_000_000), (1920, 1080, 30, 20_000_000), (2560, 1440, 30, 6_000_000)] {
        let replacement = try H264Encoder(width: width, height: height, fps: fps, bitrate: bitrate, startingSequence: continuedSequence)
        var output: Data?; var encodeError: String?
        replacement.onFrame = { output = $0 }; replacement.onError = { encodeError = $0 }
        try replacement.updateBitrate(3_000_000)
        replacement.encode(try pixel(width, height, value: 120))
        guard pump(until: { output != nil || encodeError != nil }), let output = output else { throw AireError(encodeError ?? "reconfiguration timeout") }
        let frame = try VideoFrame(output)
        check(frame.sequence == continuedSequence + 1, "replacement encoder preserves sequence")
        continuedSequence = frame.sequence
        try changingDecoder.decode(frame)
        replacement.stop()
    }
    check(changedImages == 4, "same decoder accepts resolution, bitrate and FPS changes")
    changingDecoder.stop()
    let sample = encoded[0]
    try sample.write(to: URL(fileURLWithPath: CommandLine.arguments[0] + "-sample.dat"))
    rejects("truncated AVCC") { _ = try VideoFrame(Data(sample.dropLast())) }
    let q = DispatchQueue.main
    let listener = try NWListener(using: networkParameters(key: key), on: .any)
    var receivedBurst = 0
    var listenerReady = false; var server: Peer?; var goodReady = false; var delivered = false; var acked = false; var wrongReady = false; var wrongEnded = false; var disconnected = false; var netError: String?
    listener.newConnectionHandler = { connection in
        let p = Peer(connection, queue: q); server = p
        p.onReady = { goodReady = true; p.send(.hello, Wire.hello(role: "sender")) }
        p.onPacket = { kind, data in
            if kind == .hello { do { _ = try Wire.checkHello(data, expected: "receiver"); for _ in 0..<VideoWindow.capacity { p.send(.video, sample) } } catch { netError = "\(error)" } }
            if kind == .ack { acked = data == Data([7]) }
        }
        p.onEnd = { _ in disconnected = true }; p.start()
    }
    listener.stateUpdateHandler = { if case .ready = $0 { listenerReady = true } }
    listener.start(queue: q)
    check(pump(until: { listenerReady }), "listener ready")
    let c = Peer(NWConnection(host: "127.0.0.1", port: listener.port!, using: try networkParameters(key: key)), queue: q)
    c.onReady = { c.send(.hello, Wire.hello(role: "receiver")) }
    c.onPacket = { kind, data in if kind == .video { receivedBurst += 1; delivered = data == sample; if receivedBurst == VideoWindow.capacity { c.send(.ack, Data([7])) } } }
    c.onEnd = { reason in if !acked { netError = reason } }; c.start()
    check(pump(until: { acked }), "TLS video and acknowledgement roundtrip")
    check(receivedBurst == VideoWindow.capacity, "TLS delivers three frames before waiting for acknowledgement")
    print("NET DEBUG: ready=\(goodReady), delivered=\(delivered), ack=\(acked), error=\(netError ?? "none")")
    check(goodReady && delivered && acked && netError == nil, "authenticated encrypted payload byte-identical")
    c.end(); 
    check(pump(until: { disconnected }), "remote disconnect observed")
    let wrong = Peer(NWConnection(host: "127.0.0.1", port: listener.port!, using: try networkParameters(key: newPairingKey())), queue: q)
    wrong.onReady = { wrongReady = true }; wrong.onEnd = { _ in wrongEnded = true }; wrong.start()
    check(pump(until: { wrongEnded }, seconds: 15), "wrong key fails connection")
    check(!wrongReady, "wrong key never authenticates")
    wrong.end(); server?.end(); listener.cancel()
    print("NETWORK: local TCP/TLS only; physical Wi-Fi and Intel Catalina remain untested")
} catch { print("FAIL: unexpected error \(error)"); failures += 1 }
print("RESULT: \(failures) failures")
exit(failures == 0 ? 0 : 1)
