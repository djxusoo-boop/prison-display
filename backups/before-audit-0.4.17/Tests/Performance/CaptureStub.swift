import Foundation
import CoreVideo
import CoreGraphics

// Synthetic source: exercises the real sender, encoder and TLS without screen permission.
final class Capture {
    var showsCursor = false
    var onStatus: ((String) -> Void)?
    var onRecoverableError: ((String) -> Void)?
    var onPixel: ((CVPixelBuffer) -> Void)?
    var onError: ((String) -> Void)?
    private var timer: DispatchSourceTimer?
    private var queue: DispatchQueue?
    func start(displayID: CGDirectDisplayID, width: Int, height: Int, fps: Int, queue: DispatchQueue, completion: @escaping (String?) -> Void) {
        self.queue = queue
        var frame = 0
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / fps))
        timer.setEventHandler { [weak self] in
            var pixel: CVPixelBuffer?
            let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
            guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs, &pixel) == 0, let pixel = pixel else { return }
            CVPixelBufferLockBaseAddress(pixel, [])
            let base = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt32.self)
            let stride = CVPixelBufferGetBytesPerRow(pixel) / 4
            frame += 1
            for y in 0..<height { for x in 0..<width {
                let shifted = x + frame * 8
                let v = UInt32(((shifted / 16) ^ (y / 16)) & 255)
                base[y * stride + x] = 0xFF000000 | (v << 16) | (((v * 3) & 255) << 8) | ((v * 7) & 255)
            }}
            CVPixelBufferUnlockBaseAddress(pixel, [])
            self?.onPixel?(pixel)
        }
        self.timer = timer; timer.resume(); completion(nil)
    }
    func stop(completion: @escaping () -> Void) {
        timer?.cancel(); timer = nil
        queue?.asyncAfter(deadline: .now() + 0.02, execute: completion)
    }
}
