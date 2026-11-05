#import <dlfcn.h>
#import "../../Sources/VirtualDisplay.h"
#import <math.h>
int main(void) { @autoreleasepool {
    double original = [ADBrightness read];
    if (original < 0) { puts("FAIL brightness read"); return 1; }
    BOOL success = YES;
    for (NSNumber *number in @[@0.5, @0.6]) {
        double requested = number.doubleValue, actual = [ADBrightness apply:requested];
        printf("requested=%.2f actual=%.4f\n", requested, actual);
        success = success && actual >= 0 && fabs(actual-requested) < 0.025;
    }
    success = success && [ADBrightness apply:0] < 0 && [ADBrightness apply:NAN] < 0 && [ADBrightness apply:1.01] < 0;
    // Restore exactly, including a pre-existing level below the slider's safe minimum.
    void *library = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY);
    int (*set)(CGDirectDisplayID, float) = dlsym(library, "DisplayServicesSetBrightness");
    CGDirectDisplayID displays[32]; uint32_t count=0; CGGetOnlineDisplayList(32,displays,&count);
    for(uint32_t i=0;i<count;i++) if(CGDisplayIsBuiltin(displays[i]) && CGDisplayVendorNumber(displays[i])!=0xA1DE) set(displays[i],(float)original);
    double restored=[ADBrightness read]; success=success && restored>=0 && fabs(restored-original)<0.025;
    printf("restored=%.4f original=%.4f RESULT %s\n",restored,original,success?"PASS":"FAIL");
    return success?0:1;
} }
