import AppKit
import CoreText
import CoreImage
let width = 1920, height = 1080
func image(_ step: Int) throws -> CVPixelBuffer {
    var result: CVPixelBuffer?
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &result)
    guard let pixel = result else { throw AireError("Pixel buffer") }
    CVPixelBufferLockBaseAddress(pixel, [])
    defer { CVPixelBufferUnlockBaseAddress(pixel, []) }
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
    ctx.setFillColor(CGColor(gray: 0.08, alpha: 1));ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for row in 0..<40 {
        let text = "PRISON DISPLAY  v\(AppVersion.current)    Texto pequeño: 0123456789    FL Studio — pista \(row)"
        let attr = NSAttributedString(string: text, attributes: [.font:NSFont.monospacedSystemFont(ofSize: 17, weight: .regular), .foregroundColor:NSColor.white])
        let line = CTLineCreateWithAttributedString(attr)
        ctx.textPosition = CGPoint(x: 30 + step % 40, y: 30 + row * 25)
        CTLineDraw(line, ctx)
        ctx.setStrokeColor(CGColor(red: 0.5, green: 0.4, blue: 1, alpha: 1));ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: 1200, y: 30+row*25));ctx.addLine(to: CGPoint(x: 1870, y: 30+row*25 + step%10));ctx.strokePath()
    }
    return pixel
}
func pump(timeout: Double = 2, _ f: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while !f(), Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.001)) }
    return f()
}
var failures = 0
let bitrateTrials = CommandLine.arguments.contains("--bitrates")
let tuningTrials = CommandLine.arguments.contains("--tuning")
let cases: [(Int, Int?)] = tuningTrials ? [(12_000_000,32),(20_000_000,36),(40_000_000,36),(40_000_000,32)] : (bitrateTrials ? [12_000_000,20_000_000,40_000_000,60_000_000].map { ($0, 32) } : [(2_000_000,nil),(2_000_000,32),(2_000_000,36)])
for (rate, cap) in cases {
    let encoder = try H264Encoder(width: width, height: height, fps: 60, bitrate: rate, maxFrameQP: cap)
    let decoder = H264Decoder()
    var bytes = 0
    var packets: [Data] = [], dropped = 0, error: String?
    var lastPixel: CVPixelBuffer?
    encoder.onFrame = { bytes += $0.count; packets.append($0) };encoder.onDropped = { dropped += 1 };encoder.onError = { error = $0 }
    decoder.onPixel = { lastPixel = $0 }
    var errors: [Double] = []
    for step in 0..<90 {
        let original = try image(step);let count = packets.count, drops = dropped
        encoder.encode(original)
        guard pump(timeout: step == 0 ? 10 : 2, { packets.count > count || dropped > drops || error != nil }), error == nil else { print("QUALITY ERROR", error ?? "encoder callback timeout"); failures += 1;break }
        if packets.count > count {
            try decoder.decode(VideoFrame(packets.last!))
            guard let decoded = lastPixel else { failures += 1;break }
            CVPixelBufferLockBaseAddress(original, .readOnly);CVPixelBufferLockBaseAddress(decoded, .readOnly)
            let a = CVPixelBufferGetBaseAddress(original)!.assumingMemoryBound(to: UInt8.self), b = CVPixelBufferGetBaseAddress(decoded)!.assumingMemoryBound(to: UInt8.self)
            let sa = CVPixelBufferGetBytesPerRow(original), sb = CVPixelBufferGetBytesPerRow(decoded)
            var sum = 0.0, count = 0.0
            for y in stride(from: 0, to: height, by: 2) { for x in stride(from: 0, to: width, by: 2) {
                let d = Double(a[y*sa+x*4])-Double(b[y*sb+x*4]);sum += d*d;count += 1
            } }
            CVPixelBufferUnlockBaseAddress(original, .readOnly);CVPixelBufferUnlockBaseAddress(decoded, .readOnly)
            errors.append(10 * log10(255*255/(max(0.01,sum/count))))
            if step == 89 {
                let ci = CIImage(cvPixelBuffer: decoded), context = CIContext()
                try context.writePNGRepresentation(of: ci, to: URL(fileURLWithPath:"build/ImageQuality-\(rate)-\(cap == nil ? "original" : "limited-\(cap!)").png"), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            }
        }
        RunLoop.current.run(until:Date().addingTimeInterval(0.016))
    }
    errors.sort()
    print("QUALITY target=\(rate) bytes=\(bytes) cap=\(cap ?? 0) applied=\(encoder.qualityLimitApplied) decoded=\(errors.count) dropped=\(dropped) PSNRmedian=\(errors.isEmpty ? 0 : errors[errors.count/2]) PSNRmin=\(errors.first ?? 0)")
    if errors.count == 0 || (cap != nil && !encoder.qualityLimitApplied) { failures += 1 }
    encoder.stop();decoder.stop()
}
print("RESULT: \(failures) failures; generated text, no desktop captured")
exit(failures == 0 ? 0 : 1)
