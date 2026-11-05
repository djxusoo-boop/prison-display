#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
NS_ASSUME_NONNULL_BEGIN
@interface ADLegacyCapture : NSObject
@property(nonatomic, copy, nullable) void (^onPixel)(CVPixelBufferRef);
@property(nonatomic, copy, nullable) void (^onError)(NSString *);
- (nullable NSString *)startDisplay:(CGDirectDisplayID)display width:(NSUInteger)width height:(NSUInteger)height fps:(NSUInteger)fps cursor:(BOOL)cursor queue:(dispatch_queue_t)queue;
- (void)stopWithCompletion:(void (^)(void))completion;
@end
NS_ASSUME_NONNULL_END
