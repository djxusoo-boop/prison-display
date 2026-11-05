import Foundation
import CoreVideo
import Darwin
setbuf(stdout, nil)
var failures = 0
func check(_ ok: Bool, _ label: String) { print(ok ? "PASS:" : "FAIL:", label); if !ok { failures += 1 } }
func pixel(_ width: Int, _ height: Int, _ value: UInt8) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
    guard status == 0, let p = buffer else { throw AireError("No se pudo generar imagen") }
    CVPixelBufferLockBaseAddress(p, [])
    let ptr = CVPixelBufferGetBaseAddress(p)!.assumingMemoryBound(to: UInt8.self)
    for y in 0..<height { for x in 0..<width { let i = y * CVPixelBufferGetBytesPerRow(p) + x * 4; ptr[i] = value; ptr[i+1] = value; ptr[i+2] = value; ptr[i+3] = 255 } }
    CVPixelBufferUnlockBaseAddress(p, [])
    return p
}
do {
    for (width,height,fps) in [(1280,720,30),(1920,1080,30)] {
        let encoder = try H264Encoder(width: width, height: height, fps: fps, bitrate: 6_000_000)
        let decoder = H264Decoder()
        var received = 0; var errors: [String] = []; var imageFailures = 0
        decoder.onPixel = { p in
            received += 1
            CVPixelBufferLockBaseAddress(p, .readOnly)
            let ptr = CVPixelBufferGetBaseAddress(p)!.assumingMemoryBound(to: UInt8.self)
            if CVPixelBufferGetWidth(p) != width || CVPixelBufferGetHeight(p) != height || (0...2).contains(where: { abs(Int(ptr[$0])-120) > 10 }) { imageFailures += 1 }
            CVPixelBufferUnlockBaseAddress(p, .readOnly)
        }
        encoder.onError = { errors.append($0) }
        encoder.onFrame = { data in do { try decoder.decode(VideoFrame(data)) } catch { errors.append("\(error)") } }
        let image = try pixel(width,height,120)
        for _ in 0..<60 {
            encoder.encode(image)
            RunLoop.current.run(until: Date().addingTimeInterval(1.0 / Double(fps)))
        }
        encoder.stop()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        print("ENCODER",width,height,"frames",received,"errors",errors,"hardware",encoder.hardware)
        check(errors.isEmpty && received == 60 && imageFailures == 0,"Intel physical encoder/decoder \(width)x\(height), correct pixels and all frames")
        check(encoder.hardware && decoder.hardware,"Intel hardware acceleration")
        decoder.stop()
    }
} catch { print("ERROR:",error); failures += 1 }
print("RESULT:",failures,"failures")
exit(failures == 0 ? 0 : 1)
