#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#import <CoreVideo/CoreVideo.h>
@interface ADSurfaceLease : NSObject
- (instancetype)initWithSurface:(IOSurfaceRef)surface;
@end
static int failures = 0;
static void check(BOOL condition, const char *text) { printf("%s: %s\n", condition ? "PASS" : "FAIL", text); if (!condition) failures++; }
int main(void) {
    @autoreleasepool {
        NSDictionary *properties = @{(__bridge NSString *)kIOSurfaceWidth:@64, (__bridge NSString *)kIOSurfaceHeight:@64, (__bridge NSString *)kIOSurfaceBytesPerElement:@4, (__bridge NSString *)kIOSurfaceBytesPerRow:@256, (__bridge NSString *)kIOSurfaceAllocSize:@16384, (__bridge NSString *)kIOSurfacePixelFormat:@(kCVPixelFormatType_32BGRA)};
        IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)properties);
        check(surface != NULL, "synthetic surface created");
        if (!surface) return 1;
        int original = IOSurfaceGetUseCount(surface);
        for (int iteration = 0; iteration < 100; iteration++) {
            CVPixelBufferRef pixel = NULL;
            if (CVPixelBufferCreateWithIOSurface(NULL, surface, NULL, &pixel) != kCVReturnSuccess) { check(NO,"surface wraps as a pixel buffer"); break; }
            int wrapped = IOSurfaceGetUseCount(surface);
            ADSurfaceLease *lease = [[ADSurfaceLease alloc] initWithSurface:surface];
            CVBufferSetAttachment(pixel, CFSTR("local.prisondisplay.surface-lease"), (__bridge CFTypeRef)lease, kCVAttachmentMode_ShouldNotPropagate);
            lease = nil;
            if (IOSurfaceGetUseCount(surface) != wrapped+1) { check(NO,"buffer holds its usage lease"); break; }
            CVPixelBufferRetain(pixel); CVPixelBufferRelease(pixel);
            if (IOSurfaceGetUseCount(surface) != wrapped+1) { check(NO,"an asynchronous owner preserves the lease"); break; }
            CVPixelBufferRelease(pixel);
            if (IOSurfaceGetUseCount(surface) != original) { check(NO,"final buffer release returns every usage lease"); break; }
        }
        check(IOSurfaceGetUseCount(surface) == original && failures == 0, "100 asynchronous buffer lifetimes return all leases");
        CFRelease(surface);
    }
    printf("RESULT: %d failures; synthetic surfaces, no screen capture\n", failures);
    return failures ? 1 : 0;
}
