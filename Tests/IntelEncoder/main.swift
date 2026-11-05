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
    let pipeline = try H264Encoder(width: 1280, height: 720, fps: 30, bitrate: 6_000_000, pipelined: true)
    let pipelineDecoder = H264Decoder()
    var stamps: [(UInt64, UInt64)] = [], pipelineErrors: [String] = [], smallFrames = 0, pipelinePixels = 0
    pipeline.onError = { pipelineErrors.append($0) }
    pipelineDecoder.onPixel = { _ in pipelinePixels += 1 }
    pipeline.onFrame = { data in do {
        let frame = try VideoFrame(data); stamps.append((frame.sequence, frame.timestamp))
        if frame.avcc.count < 150 { smallFrames += 1 }
        try pipelineDecoder.decode(frame)
    } catch { pipelineErrors.append("\(error)") } }
    let reference = try pixel(1280, 720, 120)
    for index in 1...16 { pipeline.encode(reference, capturedAt: UInt64(index)*1000); RunLoop.current.run(until: Date().addingTimeInterval(1.0/30)) }
    pipeline.drain(); RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    check(pipelineErrors.isEmpty && stamps.count == 16 && pipelinePixels == 16, "pipelined Intel encodes and decodes every dependent frame")
    check(stamps.enumerated().allSatisfy { $0.element.0 == UInt64($0.offset+1) && $0.element.1 == UInt64($0.offset+1)*1000 }, "asynchronous output preserves each frame's sequence and capture timestamp")
    check(smallFrames >= 10, "dependent frames preserve compression instead of flushing each image as a keyframe")
    pipeline.stop(); pipelineDecoder.stop()
    let compatible = try H264Encoder(width: 640, height: 360, fps: 30, bitrate: 6_000_000, startingSequence: 100, pipelined: true, compatibilityLowLatency: true)
    let compatibleDecoder = H264Decoder(), compatibleLock = NSLock()
    var compatibleStamps: [(UInt64, UInt64)] = [], compatibleErrors: [String] = [], compatiblePixels = 0
    compatible.onError = { error in compatibleLock.lock(); compatibleErrors.append(error); compatibleLock.unlock() }
    compatibleDecoder.onPixel = { _ in compatiblePixels += 1 }
    compatible.onFrame = { data in
        compatibleLock.lock(); defer { compatibleLock.unlock() }
        do { let frame = try VideoFrame(data); try compatibleDecoder.decode(frame); compatibleStamps.append((frame.sequence,frame.timestamp)) }
        catch { compatibleErrors.append("\(error)") }
    }
    let small = try pixel(640, 360, 120)
    compatible.enablePipelining()
    check(compatible.inputCapacity == 1, "compatible software encoder keeps a single reserved input despite auxiliary handshake")
    for index in 1...12 {
        compatible.encode(small, capturedAt: UInt64(index)*1000)
        let end = Date().addingTimeInterval(2)
        while Date() < end {
            compatibleLock.lock(); let arrived = compatibleStamps.count >= index; compatibleLock.unlock()
            if arrived { break }; RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }
    compatible.stop(); compatible.stop()
    compatibleLock.lock()
    check(compatibleErrors.isEmpty && compatibleStamps.count == 12 && compatiblePixels == 12 && !compatible.hardware, "compatible encoder emits and decodes each isolated image without waiting for another capture")
    check(compatibleStamps.enumerated().allSatisfy { $0.element.0 == UInt64($0.offset+101) && $0.element.1 == UInt64($0.offset+1)*1000 }, "queued compatible output keeps its frame sequence and original timestamp")
    compatibleLock.unlock(); compatibleDecoder.stop()
    weak var releasedEncoder: H264Encoder?
    do {
        let retiring = try H264Encoder(width: 640, height: 360, fps: 30, bitrate: 6_000_000, compatibilityLowLatency: true)
        releasedEncoder = retiring; retiring.encode(small)
    }
    let retirementDeadline = Date().addingTimeInterval(4)
    while releasedEncoder != nil && Date() < retirementDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
    check(releasedEncoder == nil, "encoder can retire on its worker after its final queued image without deadlock")
} catch { print("ERROR:",error); failures += 1 }
print("RESULT:",failures,"failures")
exit(failures == 0 ? 0 : 1)
