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
    private var session: VTCompressionSession?
    var onFrame: ((Data) -> Void)?
    var onError: ((String) -> Void)?
    var onDropped: (() -> Void)?
    private let fps: Int
    var hardware = false
    private var sequence: UInt64 = 0
    private var timestamp: UInt64 = 0
    private(set) var qualityLimitApplied = false
    init(width: Int, height: Int, fps: Int, bitrate: Int, startingSequence: UInt64 = 0, maxFrameQP: Int? = nil) throws {
        self.fps = fps
        sequence = startingSequence
        var spec: [CFString: Any] = [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true]
        // RTVC is selected for native Apple silicon; Intel uses its hardware encoder.
        #if arch(arm64)
        if #available(macOS 12.0, *) { spec[kVTVideoEncoderSpecification_EnableLowLatencyRateControl] = true }
        #endif
        let status = VTCompressionSessionCreate(allocator: kCFAllocatorDefault, width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_H264, encoderSpecification: spec as CFDictionary, imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: { ref, _, status, flags, sample in
            guard let ref = ref else { return }
            let e = Unmanaged<H264Encoder>.fromOpaque(ref).takeUnretainedValue()
            if status == noErr && (flags.contains(.frameDropped) || sample == nil) { e.onDropped?(); return }
            guard status == noErr, let sample = sample, CMSampleBufferDataIsReady(sample) else { e.onError?("Error del codificador H.264: \(status)"); return }
            do { e.onFrame?(try e.packet(sample)) } catch { e.onError?("\(error)") }
        }, refcon: Unmanaged.passUnretained(self).toOpaque(), compressionSessionOut: &session)
        guard status == noErr, let s = session else { throw AireError("No hay codificador H.264 por hardware disponible (\(status)).") }
        let properties: [CFString: Any] = [kVTCompressionPropertyKey_RealTime: true, kVTCompressionPropertyKey_AllowFrameReordering: false, kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_Main_AutoLevel, kVTCompressionPropertyKey_AverageBitRate: bitrate, kVTCompressionPropertyKey_ExpectedFrameRate: fps, kVTCompressionPropertyKey_MaxKeyFrameInterval: fps * 3, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: 3]
        let p = VTSessionSetProperties(s, propertyDictionary: properties as CFDictionary)
        guard p == noErr, VTCompressionSessionPrepareToEncodeFrames(s) == noErr else { throw AireError("No se pudo configurar el codificador (\(p)).") }
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
    func updateBitrate(_ bitrate: Int) throws {
        guard let s = session else { throw AireError("Codificador detenido.") }
        let result = VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrate))
        guard result == noErr else { throw AireError("No se pudo ajustar la calidad (\(result)).") }
    }
    func encode(_ pixel: CVPixelBuffer, capturedAt: UInt64? = nil) {
        guard let s = session else { return }
        sequence += 1; timestamp = capturedAt ?? monotonicNS()
        let status = VTCompressionSessionEncodeFrame(s, imageBuffer: pixel, presentationTimeStamp: CMTime(value: Int64(monotonicNS()), timescale: 1_000_000_000), duration: CMTime(value: 1, timescale: Int32(fps)), frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: nil)
        if status != noErr { onError?("Error al codificar: \(status)") }
    }
    private func packet(_ sample: CMSampleBuffer) throws -> Data {
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
    func stop() { if let s = session { VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid); VTCompressionSessionInvalidate(s) }; session = nil }
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
