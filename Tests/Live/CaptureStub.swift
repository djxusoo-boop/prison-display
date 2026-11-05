import Foundation
import CoreVideo
import CoreGraphics

// Synthetic source: exercises the real sender, encoder and TLS without screen permission.
final class Capture {
    static weak var latest: Capture?
    static var stopNeverResponds = false
    static var nextStartTransient = false
    static var nextStartDenied = false
    var startWasTransient = false
    var showsCursor = false
    var onStatus: ((String) -> Void)?
    var onRecoverableError: ((String) -> Void)?
    var onPixel: ((CVPixelBuffer) -> Void)?
    var onError: ((String) -> Void)?
    private var timer: DispatchSourceTimer?
    private var queue: DispatchQueue?
    func start(displayID: CGDirectDisplayID, width: Int, height: Int, fps: Int, queue: DispatchQueue, completion: @escaping (String?) -> Void) {
        self.queue = queue; Self.latest = self
        if Self.nextStartTransient {
            Self.nextStartTransient = false; startWasTransient = true
            completion("Synthetic temporary unavailable screen"); return
        }
        if Self.nextStartDenied {
            Self.nextStartDenied = false
            completion("Synthetic screen recording permission denied"); return
        }
        var pixel: CVPixelBuffer?
        let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs, &pixel) == 0, let pixel = pixel else { completion("Allocation failed"); return }
        CVPixelBufferLockBaseAddress(pixel, [])
        memset(CVPixelBufferGetBaseAddress(pixel), 100, CVPixelBufferGetBytesPerRow(pixel) * height)
        CVPixelBufferUnlockBaseAddress(pixel, [])
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / fps))
        timer.setEventHandler { [weak self] in self?.onPixel?(pixel) }
        self.timer = timer; timer.resume(); completion(nil)
    }
    func stop(completion: @escaping () -> Void) {
        timer?.cancel(); timer = nil
        if Self.stopNeverResponds { return }
        queue?.asyncAfter(deadline: .now() + 0.02, execute: completion)
    }
}
