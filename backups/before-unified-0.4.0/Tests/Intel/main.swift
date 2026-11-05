import Foundation
import CoreVideo
import CoreMedia
let file = CommandLine.arguments.dropFirst().first ?? "build/CoreTests-vectors.dat"
var failures = 0; var count = 0; var expected = 0; var width = 0; var height = 0
let decoder = H264Decoder()
decoder.onPixel = { pixel in
    count += 1
    CVPixelBufferLockBaseAddress(pixel, .readOnly)
    let base = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
    let gray = Int(base[0]); let green = Int(base[1]); let red = Int(base[2])
    CVPixelBufferUnlockBaseAddress(pixel, .readOnly)
    if abs(gray - expected) >= 10 || abs(green - expected) >= 10 || abs(red - expected) >= 10 || CVPixelBufferGetWidth(pixel) != width || CVPixelBufferGetHeight(pixel) != height {
        failures += 1; print("FAIL PIXEL", count, [gray, green, red], "expected", expected)
    }
}
do {
    let data = try Data(contentsOf: URL(fileURLWithPath: file)); var r = Reader(data); var remaining = data.count
    while remaining > 0 {
        let size = Int(try r.u32()); width = Int(try r.u16()); height = Int(try r.u16()); expected = Int(try r.bytes(1)[0])
        let packet = try r.bytes(size); remaining -= size + 9
        try decoder.decode(VideoFrame(packet))
    }
    print("DECODED", count, "HARDWARE", decoder.hardware, "FAILURES", failures)
    if count != 60 { failures += 1 }
} catch { print("FAIL", error); failures += 1 }
decoder.stop()
exit(failures == 0 ? 0 : 1)
