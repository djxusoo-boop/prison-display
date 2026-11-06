#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
@interface ADVirtualScreen : NSObject
+ (int)runHelper:(NSArray<NSString *> *)arguments;
@property(nonatomic, readonly) CGDirectDisplayID displayID;
@property(nonatomic) NSTimeInterval startupTimeout;
// Slot zero retains the original remote monitor identity; slot two is reserved
// for the optional local high-resolution monitor shown through HDMI.
@property(nonatomic) NSUInteger screenSlot;
- (BOOL)createWidth:(NSUInteger)width height:(NSUInteger)height error:(NSString **)error;
- (BOOL)resizeWidth:(NSUInteger)width height:(NSUInteger)height error:(NSString **)error;
- (void)destroy;
@end

// Only the physical built-in panel; excludes PRISON DISPLAY virtual desktops.
@interface ADBrightness : NSObject
+ (double)read;
+ (double)apply:(double)level;
+ (double)readDisplay:(CGDirectDisplayID)display;
+ (double)applyDisplay:(CGDirectDisplayID)display level:(double)level;
@end
