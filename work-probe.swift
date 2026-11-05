import Foundation
import VideoToolbox
for (name, specification) in [
("require", [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true] as [CFString: Any]),
("require low", [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true, kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true])
] {
var session: VTCompressionSession?
let status = VTCompressionSessionCreate(allocator: nil, width: 1280, height: 720, codecType: kCMVideoCodecType_H264, encoderSpecification: specification as CFDictionary, imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: nil, refcon: nil, compressionSessionOut: &session)
print(name, status)
if let s = session {
for key in [kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder, kVTCompressionPropertyKey_EncoderID] {
var value: Unmanaged<CFTypeRef>?
let result = VTSessionCopyProperty(s, key: key, allocator: nil, valueOut: &value)
print(key, result, value?.takeRetainedValue() as Any)
}
VTCompressionSessionInvalidate(s)
}
}
