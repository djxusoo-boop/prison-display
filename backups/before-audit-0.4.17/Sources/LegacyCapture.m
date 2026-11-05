#import "LegacyCapture.h"
#import <IOSurface/IOSurface.h>

// Public capture API for systems preceding ScreenCaptureKit. Intel encoders
// retain input buffers beyond completion, so never lend them the three surfaces
// owned by WindowServer: copy into a bounded, reusable encoder buffer pool.
@implementation ADLegacyCapture {
    CGDisplayStreamRef _stream;
    dispatch_queue_t _queue;
    BOOL _stopped;
    CVPixelBufferPoolRef _pool;
    ADLegacyCapture *_stopLease;
    void (^_stopCompletion)(void);
    BOOL _trace;
    NSUInteger _callbacks, _complete, _dropped;
}
- (void)finishStop {
    if (_stream) { CFRelease(_stream); _stream = NULL; }
    if (_pool) { CFRelease(_pool); _pool = NULL; }
    void (^completion)(void) = _stopCompletion; _stopCompletion = nil;
    _stopLease = nil;
    if (completion) completion();
}
- (NSString *)startDisplay:(CGDirectDisplayID)display width:(NSUInteger)width height:(NSUInteger)height fps:(NSUInteger)fps cursor:(BOOL)cursor queue:(dispatch_queue_t)queue {
    if (_stream || !width || !height || !fps) return @"Configuración de captura inválida.";
    _queue = queue; _stopped = NO;
    _trace = getenv("PRISON_CAPTURE_TRACE") != NULL;
    NSDictionary *pixels = @{(__bridge NSString *)kCVPixelBufferWidthKey: @(width), (__bridge NSString *)kCVPixelBufferHeightKey: @(height), (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA), (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}};
    if (CVPixelBufferPoolCreate(NULL, NULL, (__bridge CFDictionaryRef)pixels, &_pool) != kCVReturnSuccess) return @"No se pudieron preparar los buffers de captura.";
    NSDictionary *properties = @{
        (__bridge NSString *)kCGDisplayStreamShowCursor: @(cursor),
        (__bridge NSString *)kCGDisplayStreamMinimumFrameTime: @(1.0/fps),
        (__bridge NSString *)kCGDisplayStreamQueueDepth: @3,
        (__bridge NSString *)kCGDisplayStreamPreserveAspectRatio: @YES
    };
    __weak ADLegacyCapture *weak = self;
    _stream = CGDisplayStreamCreateWithDispatchQueue(display, width, height, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)properties, queue, ^(CGDisplayStreamFrameStatus status, uint64_t time, IOSurfaceRef surface, CGDisplayStreamUpdateRef update) {
        ADLegacyCapture *capture = weak;
        if (capture) {
            capture->_callbacks++;
            if (status == kCGDisplayStreamFrameStatusFrameComplete) capture->_complete++;
            if (capture->_trace && (capture->_callbacks <= 6 || capture->_callbacks % 30 == 0)) fprintf(stderr, "CAPTURE callbacks=%lu complete=%lu poolDrops=%lu status=%d\n", (unsigned long)capture->_callbacks, (unsigned long)capture->_complete, (unsigned long)capture->_dropped, (int)status);
        }
        if (capture && status == kCGDisplayStreamFrameStatusStopped) {
            BOOL unexpected = !capture->_stopped;
            capture->_stopped = YES; [capture finishStop];
            if (unexpected && capture.onError) capture.onError(@"La captura de pantalla se ha detenido.");
            return;
        }
        if (!capture || capture->_stopped || status != kCGDisplayStreamFrameStatusFrameComplete || !surface) return;
        uint64_t now = CVGetCurrentHostTime();
        // Skip obsolete notifications before the expensive surface fence/copy.
        // displayTime and the CV host clock both use mach_absolute_time units.
        if (capture->_complete > 1 && time && now >= time && (double)(now-time)/CVGetHostClockFrequency() > 0.1) { capture->_dropped++; return; }
        CFAbsoluteTime copyStarted = capture->_trace ? CFAbsoluteTimeGetCurrent() : 0;
        CVPixelBufferRef pixel = NULL;
        NSDictionary *limits = @{(__bridge NSString *)kCVPixelBufferPoolAllocationThresholdKey: @6};
        CVReturn result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(NULL, capture->_pool, (__bridge CFDictionaryRef)limits, &pixel);
        if (result == kCVReturnWouldExceedAllocationThreshold) { capture->_dropped++; return; } // Latest frame, bounded memory.
        if (result != kCVReturnSuccess || !pixel) {
            if (capture.onError) capture.onError(@"No se pudo leer la imagen de esta pantalla.");
            return;
        }
        CVReturn locked = CVPixelBufferLockBaseAddress(pixel, 0);
        IOReturn surfaceLocked = IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL);
        BOOL valid = locked == kCVReturnSuccess && surfaceLocked == kIOReturnSuccess && IOSurfaceGetWidth(surface) >= width && IOSurfaceGetHeight(surface) >= height;
        if (valid) {
            const uint8_t *source = IOSurfaceGetBaseAddress(surface);
            uint8_t *destination = CVPixelBufferGetBaseAddress(pixel);
            size_t sourceStride = IOSurfaceGetBytesPerRow(surface), destinationStride = CVPixelBufferGetBytesPerRow(pixel);
            valid = source && destination && sourceStride >= width*4 && destinationStride >= width*4;
            if (valid) for (NSUInteger y = 0; y < height; y++) memcpy(destination+y*destinationStride, source+y*sourceStride, width*4);
        }
        if (surfaceLocked == kIOReturnSuccess) IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
        if (locked == kCVReturnSuccess) CVPixelBufferUnlockBaseAddress(pixel, 0);
        if (!valid) { CVPixelBufferRelease(pixel); if (capture.onError) capture.onError(@"No se pudo copiar la imagen de esta pantalla."); return; }
        if (capture->_trace && (capture->_complete <= 6 || capture->_complete % 30 == 0)) fprintf(stderr, "CAPTURE copyMS=%.3f\n", (CFAbsoluteTimeGetCurrent()-copyStarted)*1000);
        if (capture.onPixel) capture.onPixel(pixel);
        CVPixelBufferRelease(pixel);
    });
    if (!_stream) { [self finishStop]; return @"macOS no pudo preparar la captura de esta pantalla."; }
    CGError result = CGDisplayStreamStart(_stream);
    if (result != kCGErrorSuccess) { [self finishStop]; return [NSString stringWithFormat:@"No se pudo iniciar la captura (%d).", result]; }
    return nil;
}
- (void)stopWithCompletion:(void (^)(void))completion {
    _stopped = YES;
    if (_stream) {
        _stopLease = self; _stopCompletion = [completion copy];
        if (CGDisplayStreamStop(_stream) != kCGErrorSuccess) [self finishStop];
    } else if (_queue) dispatch_async(_queue, completion); else completion();
}
- (void)dealloc { if (_stream) { CGDisplayStreamStop(_stream); CFRelease(_stream); } if (_pool) CFRelease(_pool); }
@end
