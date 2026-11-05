import AppKit
setbuf(stdout, nil)
if CommandLine.arguments.contains("shared-capture") { setenv("PRISON_CAPTURE_SHARED", "1", 1) }
if CommandLine.arguments.contains("nv12-capture") { setenv("PRISON_CAPTURE_NV12", "1", 1) }
if CommandLine.arguments.contains("baseline") { setenv("PRISON_ENCODER_BASELINE", "1", 1) }
if CommandLine.arguments.contains("software") { setenv("PRISON_ENCODER_SOFTWARE", "1", 1) }
let queue = DispatchQueue(label: "CaptureCodec", qos: .userInteractive), capture = Capture(), activity = StreamActivity()
let encoder = try H264Encoder(width: 1280, height: 720, fps: 30, bitrate: Int(CommandLine.arguments[1])!, pipelined: !CommandLine.arguments.contains("flush"), compatibilityLowLatency: CommandLine.arguments.contains("software"))
var latest = LatestFrame<(CVPixelBuffer, UInt64)>(), pending = 0, captured = 0, encoded = 0, bytes = 0
var done = false, errors: [String] = [], latencies: [Double] = []
func submit() {
    guard pending < 3, let (pixel, timestamp) = latest.take() else { return }
    pending += 1; encoder.encode(pixel, capturedAt: timestamp)
}
encoder.onFrame = { data in queue.async {
    do { let frame = try VideoFrame(data); pending -= 1; encoded += 1; bytes += data.count; latencies.append(Double(monotonicNS()-frame.timestamp)/1e6); submit() }
    catch { errors.append("\(error)") }
} }
encoder.onError = { error in queue.async { errors.append(error) } }
encoder.onDropped = { queue.async { pending -= 1; submit() } }
capture.onPixel = { pixel in captured += 1; latest.offer((pixel, monotonicNS())); submit() }
capture.onError = { errors.append($0) }
queue.async { activity.start(); capture.start(displayID: CGMainDisplayID(), width: 1280, height: 720, fps: 30, queue: queue) { error in if let error = error { errors.append(error) } } }
let began = Date(), deadline = began.addingTimeInterval(20)
while Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
queue.async { capture.onPixel = nil; latest.clear(); capture.stop { queue.async { encoder.drain(); encoder.stop(); activity.stop(); queue.async { done = true } } } }
let stopped = Date().addingTimeInterval(10)
while !done && Date() < stopped { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
latencies.sort()
print("RESULT captured", captured, "encoded",encoded,"fps",Double(encoded)/20,"bytes",bytes,"medianEncodeMS",latencies.isEmpty ? 0 : latencies[latencies.count/2],"p95EncodeMS",latencies.isEmpty ? 0 : latencies[min(latencies.count-1,latencies.count*95/100)],"errors", errors)
exit(done && encoded > 0 && errors.isEmpty ? 0 : 1)
