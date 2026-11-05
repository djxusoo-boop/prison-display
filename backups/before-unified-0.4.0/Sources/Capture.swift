import Foundation
import ScreenCaptureKit
import CoreMedia

@available(macOS 12.3, *)
final class Capture: NSObject, SCStreamOutput, SCStreamDelegate {
    var showsCursor = false
    private(set) var startWasTransient = false
    private var stream: SCStream?
    private var queue: DispatchQueue?
    private var stopped = false
    private var starting = false
    private var availability: RetriedOperation<SCDisplay>?
    var onRecoverableError: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    private var stopCallbacks: [() -> Void] = []
    var onPixel: ((CVPixelBuffer) -> Void)?
    var onError: ((String) -> Void)?
    func start(displayID: CGDirectDisplayID, width: Int, height: Int, fps: Int, queue: DispatchQueue, completion: @escaping (String?) -> Void) {
        self.queue = queue
        startWasTransient = false
        guard CGPreflightScreenCaptureAccess() else {
            queue.async { completion("Falta el permiso de pantalla. En Ajustes → Privacidad y seguridad → Grabación de pantalla, añade PRISON DISPLAY MacBook desde Aplicaciones y vuelve a abrir la app.") }
            return
        }
        let request = RetriedOperation<SCDisplay>(queue: queue, shouldRetry: CaptureFailure.isTransient, request: { done in
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
                if let error = error { done(.failure(error)) }
                else if let display = content?.displays.first(where: { $0.displayID == displayID }) { done(.success(display)) }
                else { done(.failure(CaptureFailure.unavailable)) }
            }
        }, completion: { [weak self] result in
                guard let self = self, !self.stopped else { return }
                guard case .success(let display) = result else {
                    if case .failure(let error) = result {
                        self.startWasTransient = CaptureFailure.isTransient(error)
                        let e = error as NSError
                        completion(e.domain == SCStreamErrorDomain && e.code == -3801 ? "macOS ha denegado la captura. Revisa el permiso de Grabación de pantalla de PRISON DISPLAY MacBook." : "No se pudo preparar la pantalla: " + error.localizedDescription)
                    }
                    return
                }
                let config = SCStreamConfiguration(); config.width = width; config.height = height
                config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(fps)); config.queueDepth = 3
                #if DIAGNOSTIC_SCENE
                if CommandLine.arguments.contains("capture-five") { config.queueDepth = 5 }
                #endif
                if #available(macOS 14.0, *) { config.preservesAspectRatio = true }
                config.pixelFormat = kCVPixelFormatType_32BGRA; config.showsCursor = self.showsCursor
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                do { try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue) }
                catch { self.startWasTransient = CaptureFailure.isTransient(error); completion("\(error)"); return }
                self.stream = stream; self.starting = true
                stream.startCapture { error in queue.async {
                    self.starting = false
                    if self.stopped { self.finishStop() }
                    else {
                        self.startWasTransient = error.map(CaptureFailure.isTransient) ?? false
                        completion(error?.localizedDescription)
                    }
                }}
        })
        request.onRetry = { [weak self] _ in self?.onStatus?("Esperando a que macOS prepare la pantalla…") }
        availability = request; request.start()
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue?.async { [weak self] in
            guard let self = self, !self.stopped else { return }
            if CaptureFailure.isTransient(error) { self.onRecoverableError?(error.localizedDescription) }
            else { self.onError?(error.localizedDescription) }
        }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !stopped, type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onPixel?(pixel)
    }
    func stop(completion: @escaping () -> Void) {
        guard let queue = queue else { completion(); return }
        queue.async {
            self.stopped = true; self.availability?.cancel(); self.availability = nil; self.stopCallbacks.append(completion)
            if !self.starting { self.finishStop() }
        }
    }
    private func finishStop() {
        if let stream = stream {
            self.stream = nil
            stream.stopCapture { _ in self.queue?.async { self.completeStop() } }
        } else { completeStop() }
    }
    private func completeStop() {
        let callbacks = stopCallbacks; stopCallbacks = []
        callbacks.forEach { $0() }
    }
}
