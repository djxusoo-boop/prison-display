import Foundation
import CoreVideo
import CoreGraphics

final class Capture {
    static weak var latest: Capture?
    static var periodic = false
    static var initialBeforeCompletion = false
    var startWasTransient = false
    var showsCursor = false
    var onStatus: ((String) -> Void)?
    var onRecoverableError: ((String) -> Void)?
    var onPixel: ((CVPixelBuffer) -> Void)?
    var onError: ((String) -> Void)?
    private var queue: DispatchQueue?
    private var pixel: CVPixelBuffer?
    private var timer: DispatchSourceTimer?
    func start(displayID: CGDirectDisplayID, width: Int, height: Int, fps: Int, queue: DispatchQueue, completion: @escaping (String?) -> Void) {
        Self.latest = self; self.queue = queue
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel) == 0 else { completion("Allocation failed"); return }
        if Self.initialBeforeCompletion, let pixel = pixel {
            CVPixelBufferLockBaseAddress(pixel, [])
            memset(CVPixelBufferGetBaseAddress(pixel), 120, CVPixelBufferGetBytesPerRow(pixel)*CVPixelBufferGetHeight(pixel))
            CVPixelBufferUnlockBaseAddress(pixel, []); onPixel?(pixel); completion(nil)
        } else { completion(nil); emit() }
        if Self.periodic {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now()+0.03, repeating: .milliseconds(30))
            timer.setEventHandler { [weak self] in self?.emit() }
            self.timer = timer; timer.resume()
        }
    }
    func emit() {
        queue?.async { [weak self] in
            guard let self = self, let pixel = self.pixel else { return }
            CVPixelBufferLockBaseAddress(pixel, [])
            memset(CVPixelBufferGetBaseAddress(pixel), 120, CVPixelBufferGetBytesPerRow(pixel)*CVPixelBufferGetHeight(pixel))
            CVPixelBufferUnlockBaseAddress(pixel, [])
            self.onPixel?(pixel)
        }
    }
    func stop(completion: @escaping () -> Void) { queue?.async { self.timer?.cancel(); self.timer = nil; self.onPixel = nil; completion() } }
}
