#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
@interface ADVirtualScreen : NSObject
+ (int)runHelper:(NSArray<NSString *> *)arguments;
@property(nonatomic, readonly) CGDirectDisplayID displayID;
@property(nonatomic) NSTimeInterval startupTimeout;
- (BOOL)createWidth:(NSUInteger)width height:(NSUInteger)height error:(NSString **)error;
- (BOOL)resizeWidth:(NSUInteger)width height:(NSUInteger)height error:(NSString **)error;
- (void)destroy;
@end
