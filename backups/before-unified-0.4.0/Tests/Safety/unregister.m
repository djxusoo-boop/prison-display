#import <Foundation/Foundation.h>
#import <ColorSync/ColorSync.h>
#import <CoreGraphics/CoreGraphics.h>

// One reviewed historical UUID per short-lived process. The Python controller
// bounds each call; the installed apps never run system registry maintenance.
int main(int argc, const char *argv[]) { @autoreleasepool {
    if (argc != 4) return 2;
    NSString *mode = @(argv[1]), *folder = @(argv[2]), *uuid = [@(argv[3]) uppercaseString];
    NSData *planData = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:@"device-unregister-plan.json"]];
    NSDictionary *plan = planData ? [NSJSONSerialization JSONObjectWithData:planData options:0 error:nil] : nil;
    NSDictionary *selected = nil;
    for (NSDictionary *row in plan[@"selected"]) if ([row[@"uuid"] isEqual:uuid]) { selected = row; break; }
    if (!selected || ![selected[@"cache_key"] isEqual:[@"Device.mntr." stringByAppendingString:uuid]]) return 3;
    NSNumber *serial = selected[@"serial"];
    if ([serial unsignedIntValue] == ((1280u<<16)|720u) || [serial unsignedIntValue] == ((1920u<<16)|1080u) || [serial unsignedIntValue] == ((2560u<<16)|1440u)) return 4;
    CFUUIDRef identifier = CFUUIDCreateFromString(NULL, (__bridge CFStringRef)uuid);
    if (!identifier) return 5;
    uint32_t count = 0; CGDirectDisplayID displays[128];
    if (CGGetOnlineDisplayList(128, displays, &count) != kCGErrorSuccess || count >= 128) { CFRelease(identifier); return 6; }
    for (uint32_t i=0;i<count;i++) {
        CFUUIDRef live = CGDisplayCreateUUIDFromDisplayID(displays[i]);
        BOOL same = live && CFEqual(identifier, live); if (live) CFRelease(live);
        if (same) { CFRelease(identifier); return 7; }
    }
    CFDictionaryRef current = ColorSyncDeviceCopyDeviceInfo(kColorSyncDisplayDeviceClass, identifier);
    NSDictionary *info = CFBridgingRelease(current);
    NSString *description = info[(__bridge NSString *)kColorSyncDeviceDescription];
    NSDictionary *profiles = info[(__bridge NSString *)kColorSyncFactoryProfiles];
    if ([mode isEqual:@"inspect"]) printf("INFO present=%d descriptionMatches=%d factoryCount=%lu\n", info != nil, [description isEqual:@"PRISON DISPLAY · iMac"] || [description isEqual:@"AireDisplay · iMac"], (unsigned long)profiles.count);
    BOOL exact = NO;
    for (id profile in profiles.allValues) if ([profile isKindOfClass:[NSDictionary class]]) {
        id url = profile[(__bridge NSString *)kColorSyncDeviceProfileURL];
        if ([mode isEqual:@"inspect"]) printf("URL present=%d NSURL=%d NSString=%d\n", url != nil, [url isKindOfClass:[NSURL class]], [url isKindOfClass:[NSString class]]);
        NSString *name = [url isKindOfClass:[NSURL class]] ? [url lastPathComponent] : nil;
        if ([name isEqual:selected[@"profile_name"]]) exact = YES;
    }
    // Once an ICC has been quarantined, ColorSync omits its missing URL.
    // The controller independently verifies the backed-up UUID->ICC identity
    // and hash. Require the same old offline UUID, app name and profile ID.
    BOOL missingQuarantinedURL = profiles[@"1"] != nil && ![[NSFileManager defaultManager] fileExistsAtPath:[@"/Library/ColorSync/Profiles/Displays" stringByAppendingPathComponent:selected[@"profile_name"]]];
    if (!(exact || missingQuarantinedURL) || !([description isEqual:@"PRISON DISPLAY · iMac"] || [description isEqual:@"AireDisplay · iMac"])) { CFRelease(identifier); return 8; }
    if ([mode isEqual:@"inspect"]) { puts("VERIFIED: reviewed historical UUID, matching factory profile, absent from online displays"); CFRelease(identifier); return 0; }
    if (![mode isEqual:@"unregister"] || geteuid()!=0) { CFRelease(identifier); return 9; }
    BOOL ok = ColorSyncUnregisterDevice(kColorSyncDisplayDeviceClass, identifier);
    CFRelease(identifier); puts(ok ? "UNREGISTERED" : "UNREGISTER FAILED"); return ok ? 0 : 10;
}}
