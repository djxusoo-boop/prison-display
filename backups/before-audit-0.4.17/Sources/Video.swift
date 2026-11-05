import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

struct VideoFrame {
    let sequence: UInt64
    let timestamp: UInt64
    let sps: Data
    let pps: Data
    let avcc: Data
    func serialize() -> Data {
        var d = Data(); d.u64(sequence); d.u64(timestamp)
        d.u16(UInt16(sps.count)); d.append(sps); d.u16(UInt16(pps.count)); d.append(pps); d.append(avcc); return d
    }
    init(sequence: UInt64, timestamp: UInt64, sps: Data, pps: Data, avcc: Data) {
        self.sequence = sequence; self.timestamp = timestamp; self.sps = sps; self.pps = pps; self.avcc = avcc
    }
    init(_ data: Data) throws {
        var r = Reader(data); sequence = try r.u64(); timestamp = try r.u64()
        sps = try r.bytes(Int(r.u16())); pps = try r.bytes(Int(r.u16())); avcc = try r.rest()
        guard !sps.isEmpty, !pps.isEmpty, sps.count <= 4096, pps.count <= 4096, !avcc.isEmpty else { throw AireError("Cabecera de vídeo inválida.") }
        var nal = Reader(avcc); var remaining = avcc.count
        while remaining > 0 {
            let size = Int(try nal.u32()); remaining -= 4
            guard size > 0, size <= remaining else { throw AireError("Bloque H.264 inválido.") }
            _ = try nal.bytes(size); remaining -= size
        }
    }
}
final class H264Encoder {
    private final class Stamp {
        let sequence: UInt64, timestamp: UInt64
        init(_ sequence: UInt64, _ timestamp: UInt64) { self.sequence = sequence; self.timestamp = timestamp }
    }
    private var session: VTCompressionSession?
    var onFrame: ((Data) -> Void)?
    var onError: ((String) -> Void)?
    var onDropped: (() -> Void)?
    private let fps: Int
    var hardware = false
    private let sequenceLock = NSLock()
    private var sequence: UInt64 = 0
    var lastSubmittedSequence: UInt64 { sequenceLock.lock(); defer { sequenceLock.unlock() }; return sequence }
    private(set) var inputCapacity = 1
    private(set) var qualityLimitApplied = false
    private var completeEachFrame = false
    private let compatibilityLowLatency: Bool
    private let compatibilityQueue = DispatchQueue(label: "PrisonDisplay.compatibility-encoder", qos: .userInteractive)
    private let compatibilityKey = DispatchSpecificKey<Bool>()
    init(width: Int, height: Int, fps: Int, bitrate: Int, startingSequence: UInt64 = 0, maxFrameQP: Int? = nil, pipelined: Bool = false, compatibilityLowLatency: Bool = false) throws {
        self.fps = fps
        self.compatibilityLowLatency = compatibilityLowLatency
        compatibilityQueue.setSpecific(key: compatibilityKey, value: true)
        sequence = startingSequence
        var spec: [CFString: Any] = [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true]
        if compatibilityLowLatency { spec = [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: false] }
        // RTVC is selected for native Apple silicon; Intel uses its hardware encoder.
        #if arch(arm64)
        // RTVC selects Apple's hardware-only low-latency encoder. Never pass
        // it alongside the software-only compatibility path: VideoToolbox
        // rejects that combination with kVTParameterErr (-12902).
        if !compatibilityLowLatency, #available(macOS 12.0, *) { spec[kVTVideoEncoderSpecification_EnableLowLatencyRateControl] = true }
        #endif
        let status = VTCompressionSessionCreate(allocator: kCFAllocatorDefault, width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_H264, encoderSpecification: spec as CFDictionary, imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: { ref, frame, status, flags, sample in
            guard let frame = frame else { return }
            let stamp = Unmanaged<Stamp>.fromOpaque(frame).takeRetainedValue()
            guard let ref = ref else { return }
            let e = Unmanaged<H264Encoder>.fromOpaque(ref).takeUnretainedValue()
            if status == noErr && (flags.contains(.frameDropped) || sample == nil) { e.onDropped?(); return }
            guard status == noErr, let sample = sample, CMSampleBufferDataIsReady(sample) else { e.onError?("Error del codificador H.264: \(status)"); return }
            do {
                let data = try e.packet(sample, sequence: stamp.sequence, timestamp: stamp.timestamp)
                #if DIAGNOSTIC_SCENE
                if CommandLine.arguments.contains("encoder-trace"), stamp.sequence <= 10 || stamp.sequence % 30 == 0 {
                    print("ENCODE TRACE", stamp.sequence, "bytes", data.count, "capacity", e.inputCapacity, "flush", e.completeEachFrame, "elapsedMS", Double(monotonicNS()-stamp.timestamp)/1e6)
                }
                #endif
                e.onFrame?(data)
            } catch { e.onError?("\(error)") }
        }, refcon: Unmanaged.passUnretained(self).toOpaque(), compressionSessionOut: &session)
        guard status == noErr, let s = session else { throw AireError("macOS no pudo preparar el compresor de pantalla (\(status)).") }
        var profile = kVTProfileLevel_H264_Main_AutoLevel
        #if DIAGNOSTIC_SCENE || DIAGNOSTIC_ENCODER
        if getenv("PRISON_ENCODER_BASELINE") != nil { profile = kVTProfileLevel_H264_Baseline_AutoLevel }
        #endif
        let properties: [CFString: Any] = [kVTCompressionPropertyKey_RealTime: true, kVTCompressionPropertyKey_AllowFrameReordering: false, kVTCompressionPropertyKey_ProfileLevel: profile, kVTCompressionPropertyKey_AverageBitRate: bitrate, kVTCompressionPropertyKey_ExpectedFrameRate: fps, kVTCompressionPropertyKey_MaxKeyFrameInterval: fps * 3, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: 3]
        let p = VTSessionSetProperties(s, propertyDictionary: properties as CFDictionary)
        guard p == noErr else { throw AireError("No se pudo configurar el codificador (\(p)).") }
        // RealTime is a hint, not a guarantee that a single image is emitted.
        // Our bounded pipeline submits one image at a time, so an encoder that
        // waits for a second image would deadlock the first-image handshake.
        #if arch(x86_64)
        _ = VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: NSNumber(value: 0))
        // High Sierra's Intel encoder accepts this property but can still
        // retain a lone image. Complete it explicitly before awaiting the ACK.
        completeEachFrame = compatibilityLowLatency || !pipelined
        inputCapacity = pipelined && !compatibilityLowLatency ? 2 : 1
        #endif
        let preparation = VTCompressionSessionPrepareToEncodeFrames(s)
        guard preparation == noErr else { throw AireError("No se pudo preparar el codificador (\(preparation)).") }
        // The high-quality profile limits text degradation on Apple's RTVC
        // encoder. Under overload it can drop an image rather than blur it.
        #if arch(arm64)
        if #available(macOS 12.0, *), let qp = maxFrameQP {
            qualityLimitApplied = VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxAllowedFrameQP, value: NSNumber(value: min(51, max(1, qp)))) == noErr
        }
        #endif
        var value: Unmanaged<CFTypeRef>?; VTSessionCopyProperty(s, key: kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder, allocator: nil, valueOut: &value)
        hardware = (value?.takeRetainedValue() as? NSNumber)?.boolValue == true
        // Apple’s low-latency RTVC encoder does not expose the hardware indicator.
        // Session creation requires hardware, and Apple documents RTVC as hardware-only.
        if !hardware {
            var identifier: Unmanaged<CFTypeRef>?
            VTSessionCopyProperty(s, key: kVTCompressionPropertyKey_EncoderID, allocator: nil, valueOut: &identifier)
            hardware = (identifier?.takeRetainedValue() as? String) == "com.apple.videotoolbox.videoencoder.h264.rtvc"
        }
    }
    func updateQualityLimit(_ qp: Int?) {
        #if arch(arm64)
        if #available(macOS 12.0, *), let s = session {
            let result = VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxAllowedFrameQP, value: NSNumber(value: min(51, max(1, qp ?? 51))))
            qualityLimitApplied = qp != nil && result == noErr
        }
        #endif
    }
    func enablePipelining() {
        #if arch(x86_64)
        guard !compatibilityLowLatency else { return }
        completeEachFrame = false; inputCapacity = 2
        #endif
    }
    func updateBitrate(_ bitrate: Int) throws {
        try onCodecQueue {
        guard let s = session else { throw AireError("Codificador detenido.") }
        let result = VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrate))
        guard result == noErr else { throw AireError("No se pudo ajustar la calidad (\(result)).") }
        }
    }
    func encode(_ pixel: CVPixelBuffer, capturedAt: UInt64? = nil) {
        sequenceLock.lock(); sequence += 1; let index = sequence; sequenceLock.unlock()
        let stamp = Stamp(index, capturedAt ?? monotonicNS())
        // High Sierra's software completion can wait for compression. Keep that
        // wait off the queue that receives keyboard/mouse and acknowledgements.
        // The engine reserves a bounded input slot before scheduling this job.
        if compatibilityLowLatency { compatibilityQueue.async { self.encodeOnQueue(pixel, stamp: stamp) } }
        else { encodeOnQueue(pixel, stamp: stamp) }
    }
    private func encodeOnQueue(_ pixel: CVPixelBuffer, stamp value: Stamp) {
        guard let s = session else { return }
        let stamp = Unmanaged.passRetained(value)
        let status = VTCompressionSessionEncodeFrame(s, imageBuffer: pixel, presentationTimeStamp: CMTime(value: Int64(monotonicNS()), timescale: 1_000_000_000), duration: CMTime(value: 1, timescale: Int32(fps)), frameProperties: nil, sourceFrameRefcon: stamp.toOpaque(), infoFlagsOut: nil)
        if status != noErr { stamp.release(); onError?("Error al codificar: \(status)"); return }
        if completeEachFrame {
            let completion = VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
            if completion != noErr { onError?("No se pudo completar la imagen: \(completion)") }
        }
    }
    private func onCodecQueue<Value>(_ operation: () throws -> Value) rethrows -> Value {
        if !compatibilityLowLatency || DispatchQueue.getSpecific(key: compatibilityKey) == true { return try operation() }
        return try compatibilityQueue.sync(execute: operation)
    }
    func drain() { onCodecQueue { if let session = session { let status = VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid); if status != noErr { onError?("No se pudo completar el vídeo: \(status)") } } } }
    private func packet(_ sample: CMSampleBuffer, sequence: UInt64, timestamp: UInt64) throws -> Data {
        guard let format = CMSampleBufferGetFormatDescription(sample), let block = CMSampleBufferGetDataBuffer(sample) else { throw AireError("Falta formato de vídeo.") }
        var sps = Data(), pps = Data()
        for index in 0...1 {
            var ptr: UnsafePointer<UInt8>?; var size = 0
            let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: index, parameterSetPointerOut: &ptr, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
            guard status == noErr, let p = ptr, size > 0, size <= 4096 else { throw AireError("Faltan parámetros H.264.") }
            if index == 0 { sps = Data(bytes: p, count: size) } else { pps = Data(bytes: p, count: size) }
        }
        let length = CMBlockBufferGetDataLength(block)
        guard length > 0, length < Wire.maxPacket - 9000 else { throw AireError("El fotograma excede el límite. Reduce la resolución.") }
        var avcc = Data(count: length)
        let status = avcc.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
        guard status == noErr else { throw AireError("No se pudo leer el vídeo.") }
        return VideoFrame(sequence: sequence, timestamp: timestamp, sps: sps, pps: pps, avcc: avcc).serialize()
    }
    func stop() { onCodecQueue { if let s = session { VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid); VTCompressionSessionInvalidate(s) }; session = nil } }
    deinit { stop() }
}
final class H264Decoder {
    private var session: VTDecompressionSession?
    private var format: CMVideoFormatDescription?
    private var parameters = Data()
    var onPixel: ((CVPixelBuffer) -> Void)?
    var hardware = false
    private var callbackError: OSStatus = noErr
    func decode(_ frame: VideoFrame) throws {
        var combined = Data(); combined.u16(UInt16(frame.sps.count)); combined.append(frame.sps); combined.append(frame.pps)
        if combined != parameters { try configure(frame); parameters = combined }
        guard let format = format, let session = session else { throw AireError("Decodificador no disponible.") }
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: frame.avcc.count, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: frame.avcc.count, flags: 0, blockBufferOut: &block)
        guard status == noErr, let block = block else { throw AireError("No se pudo reservar el fotograma.") }
        status = frame.avcc.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: frame.avcc.count) }
        guard status == noErr else { throw AireError("No se pudo copiar el fotograma.") }
        var sample: CMSampleBuffer?; var size = frame.avcc.count
        status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        guard status == noErr, let sample = sample else { throw AireError("Fotograma H.264 inválido.") }
        callbackError = noErr
        status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [], frameRefcon: nil, infoFlagsOut: nil)
        guard status == noErr, callbackError == noErr else { throw AireError("Error al decodificar: \(status)/\(callbackError)") }
    }
    private func configure(_ frame: VideoFrame) throws {
        stop()
        let status = frame.sps.withUnsafeBytes { a in frame.pps.withUnsafeBytes { b -> OSStatus in
            let ptrs = [a.baseAddress!.assumingMemoryBound(to: UInt8.self), b.baseAddress!.assumingMemoryBound(to: UInt8.self)]
            let sizes = [frame.sps.count, frame.pps.count]
            return CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault, parameterSetCount: 2, parameterSetPointers: ptrs, parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &format)
        }}
        guard status == noErr, let format = format else { throw AireError("Parámetros H.264 no válidos.") }
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        guard dimensions.width > 0, dimensions.height > 0, dimensions.width <= 3840, dimensions.height <= 2160 else { throw AireError("Resolución fuera de límite.") }
        var callback = VTDecompressionOutputCallbackRecord(decompressionOutputCallback: { ref, _, status, _, pixel, _, _ in
            guard let ref = ref else { return }
            let d = Unmanaged<H264Decoder>.fromOpaque(ref).takeUnretainedValue()
            d.callbackError = status
            if status == noErr, let pixel = pixel { d.onPixel?(pixel) }
        }, decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque())
        let spec = [kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true] as CFDictionary
        let attrs = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA, kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        let result = VTDecompressionSessionCreate(allocator: nil, formatDescription: format, decoderSpecification: spec, imageBufferAttributes: attrs, outputCallback: &callback, decompressionSessionOut: &session)
        guard result == noErr, let session = session else { throw AireError("No se pudo iniciar el decodificador (\(result)).") }
        VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        var value: Unmanaged<CFTypeRef>?; VTSessionCopyProperty(session, key: kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder, allocator: nil, valueOut: &value)
        hardware = (value?.takeRetainedValue() as? NSNumber)?.boolValue == true
    }
    func stop() { if let s = session { VTDecompressionSessionInvalidate(s) }; session = nil; format = nil; parameters = Data() }
    deinit { stop() }
}
