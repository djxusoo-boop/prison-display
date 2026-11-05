#import <AppKit/AppKit.h>
#import <VideoToolbox/VideoToolbox.h>
int main(void) {
    @autoreleasepool {
        printf("OS %s\n", NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String);
        for (NSString *name in @[@"CGVirtualDisplay", @"CGVirtualDisplayDescriptor", @"CGVirtualDisplayMode", @"CGVirtualDisplaySettings"]) printf("CLASS %s %s\n", name.UTF8String, NSClassFromString(name) ? "available" : "absent");
        printf("MAIN_DISPLAY %u\n", CGMainDisplayID());
        VTCompressionSessionRef session = NULL;
        NSDictionary *spec = @{(__bridge NSString *)kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder:@YES};
        OSStatus status = VTCompressionSessionCreate(NULL, 1280, 720, kCMVideoCodecType_H264, (__bridge CFDictionaryRef)spec, NULL, NULL, NULL, NULL, &session);
        printf("H264_HARDWARE %d\n", (int)status);
        if (session) { VTCompressionSessionInvalidate(session); CFRelease(session); }
    }
    return 0;
}
