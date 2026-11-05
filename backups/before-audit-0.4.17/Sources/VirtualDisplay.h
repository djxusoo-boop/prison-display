#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
@interface ADVirtualScreen : NSObject
+ (int)runHelper:(NSArray<NSString *> *)arguments;
@property(nonatomic, readonly) CGDirectDisplayID displayID;
@property(nonatomic) NSTimeInterval startupTimeout;
// Slot zero retains the original monitor identity and saved placement.
@property(nonatomic) NSUInteger screenSlot;
- (BOOL)createWidth:(NSUInteger)width height:(NSUInteger)height error:(NSString **)error;
- (BOOL)resizeWidth:(NSUInteger)width height:(NSUInteger)height error:(NSString **)error;
- (void)destroy;
@end

// Only the physical built-in panel; excludes PRISON DISPLAY virtual desktops.
@interface ADBrightness : NSObject
+ (double)read;
+ (double)apply:(double)level;
@end
