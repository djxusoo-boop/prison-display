#import "VirtualStub.h"
#import <stdatomic.h>
static atomic_uint active = 0;
unsigned int ADMockActiveDisplays(void) { return atomic_load(&active); }
@implementation ADVirtualScreen {
    CGDirectDisplayID _testID;
}
+ (int)runHelper:(NSArray<NSString *> *)arguments { return 2; }
- (CGDirectDisplayID)displayID { return _testID; }
- (BOOL)createWidth:(NSUInteger)width height:(NSUInteger)height error:(NSString **)error { if (_testID) return NO; _testID = CGMainDisplayID(); atomic_fetch_add(&active,1); return YES; }
- (BOOL)resizeWidth:(NSUInteger)width height:(NSUInteger)height error:(NSString **)error { [self destroy];return [self createWidth:width height:height error:error]; }
- (void)destroy { if (_testID) { _testID=0;atomic_fetch_sub(&active,1); } }
- (void)dealloc { [self destroy]; }
@end
