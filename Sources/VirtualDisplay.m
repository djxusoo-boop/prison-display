#import "VirtualDisplay.h"
#import <AppKit/AppKit.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <signal.h>
#import <unistd.h>
#import <string.h>
@interface CGVirtualDisplayDescriptor : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic) unsigned int maxPixelsWide, maxPixelsHigh, vendorID, productID, serialNum;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) CGPoint redPrimary, greenPrimary, bluePrimary, whitePoint;
@property(nonatomic) unsigned int serialNumber;
- (void)setDispatchQueue:(dispatch_queue_t)queue;
@end
@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(double)rate;
@end
@interface CGVirtualDisplaySettings : NSObject
@property(nonatomic) unsigned int hiDPI;
@property(nonatomic, retain) NSArray *modes;
@end
@interface CGVirtualDisplay : NSObject
@property(nonatomic, readonly) CGDirectDisplayID displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end
@interface ADVirtualScreen ()
- (void)markLayoutDirty:(CGDisplayChangeSummaryFlags)flags;
@end
static void ADLayoutChanged(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *context) {
    [(__bridge ADVirtualScreen *)context markLayoutDirty:flags];
}
static void ADWaitForExit(NSTask *task, double seconds) {
    double end = NSProcessInfo.processInfo.systemUptime + seconds;
    while (task.running && NSProcessInfo.processInfo.systemUptime < end) [NSThread sleepForTimeInterval:0.01];
}
static void ADRetireHelper(NSTask *task, NSPipe *input) {
    [input.fileHandleForWriting closeFile];
    ADWaitForExit(task, 0.3);
    if (task.running) [task terminate];
    ADWaitForExit(task, 0.35);
    // Only the child launched by this instance. A stuck display query must not
    // turn waitUntilExit into an unlimited wait in the application.
    if (task.running) kill(task.processIdentifier, SIGKILL);
    ADWaitForExit(task, 1.0);
}
static unsigned int ADLocalProfile(NSUInteger width, NSUInteger height) {
    if (width == 2560 && height == 1440) return 1;
    if (width == 3200 && height == 1800) return 2;
    if (width == 3840 && height == 2160) return 3;
    if (width == 5120 && height == 2880) return 4;
    return 15;
}
// macOS lists every size of a new virtual monitor but activates a default
// (1920×1080 on macOS 26) instead of the largest. Select the exact 1× mode.
// Returns 0 if already active, 1 if changed, -1 if unavailable.
static int ADSelectExactMode(CGDirectDisplayID display, NSUInteger width, NSUInteger height) {
    if (CGDisplayPixelsWide(display) == width && CGDisplayPixelsHigh(display) == height) return 0;
    NSDictionary *options = @{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes: @YES};
    NSArray *modes = CFBridgingRelease(CGDisplayCopyAllDisplayModes(display, (__bridge CFDictionaryRef)options));
    for (id item in modes) {
        CGDisplayModeRef mode = (__bridge CGDisplayModeRef)item;
        if (CGDisplayModeGetWidth(mode) != width || CGDisplayModeGetHeight(mode) != height || CGDisplayModeGetPixelWidth(mode) != width) continue;
        CGDisplayConfigRef config = NULL;
        if (CGBeginDisplayConfiguration(&config) != kCGErrorSuccess) return -1;
        if (CGConfigureDisplayWithDisplayMode(config, display, mode, NULL) != kCGErrorSuccess) { CGCancelDisplayConfiguration(config); return -1; }
        return CGCompleteDisplayConfiguration(config, kCGConfigureForSession) == kCGErrorSuccess ? 1 : -1;
    }
    return -1;
}
static NSString *ADLayoutKey(NSUInteger slot) {
    if (slot == 0) return @"PrisonDisplay.layout";
    if (slot == 1) return @"PrisonDisplay.layout.2";
    return @"PrisonDisplay.layout.local";
}
@implementation ADVirtualScreen {
    CGVirtualDisplay *_screen;
    NSTimer *_layoutTimer;
    NSTask *_helper;
    NSPipe *_helperInput;
    CGDirectDisplayID _helperDisplayID;
    NSUserDefaults *_preferences;
    NSLock *_layoutLock;
    BOOL _layoutDirty, _registeredLayout, _layoutTopologyDirty, _skipAbsentSave, _hadPeer, _layoutConfiguring;
}
- (CGDirectDisplayID)displayID { return _helper ? _helperDisplayID : (_screen ? _screen.displayID : 0); }
- (BOOL)createWidth:(NSUInteger)width height:(NSUInteger)height error:(NSString **)error {
    if (_helper) { if (error) *error = @"Ya existe una pantalla virtual."; return NO; }
    if (![[NSProcessInfo processInfo].arguments containsObject:@"--virtual-display-helper"]) return [self startHelperWidth:width height:height error:error];
    if (_screen) { if (error) *error = @"Ya existe una pantalla virtual."; return NO; }
    Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
    if (!descriptorClass || !displayClass || !modeClass || !settingsClass) {
        if (error) *error = @"Esta versión de macOS no permite crear la pantalla virtual. Puedes duplicar.";
        return NO;
    }
    @try {
        CGVirtualDisplayDescriptor *d = [[descriptorClass alloc] init];
        d.name = self.screenSlot == 0 ? @"PRISON DISPLAY · Pantalla remota" : (self.screenSlot == 1 ? @"PRISON DISPLAY · Pantalla 2" : @"PRISON DISPLAY · Monitor virtual local");
        d.maxPixelsWide = (unsigned int)width; d.maxPixelsHigh = (unsigned int)height;
        d.sizeInMillimeters = CGSizeMake(width * 25.4 / 100, height * 25.4 / 100);
        d.vendorID = 0xA1DE; d.productID = 1 + (unsigned int)self.screenSlot;
        // Reuse one identity per resolution. Random identities accumulate ICC
        // profiles and display records on every reconnect or configuration test.
        unsigned int serial = ((unsigned int)width << 16) | (unsigned int)height;
        // The local HDMI virtual monitor keeps a separate product identity per
        // desktop size so a remembered mode of another size is never reused.
        if (self.screenSlot == 2) d.productID = 0x5200u | ADLocalProfile(width, height);
        d.serialNum = serial;
        if ([d respondsToSelector:@selector(setSerialNumber:)]) d.serialNumber = serial;
        d.redPrimary = CGPointMake(0.64, 0.33); d.greenPrimary = CGPointMake(0.30, 0.60);
        d.bluePrimary = CGPointMake(0.15, 0.06); d.whitePoint = CGPointMake(0.3127, 0.3290);
        [d setDispatchQueue:dispatch_queue_create("PrisonDisplay.virtual-events", DISPATCH_QUEUE_SERIAL)];
        _screen = [[displayClass alloc] initWithDescriptor:d];
        CGVirtualDisplaySettings *s = [[settingsClass alloc] init];
        // 1× surfaces: the requested size is real desktop space and costs no
        // hidden 2× backing store. macOS still lists smaller default modes, so
        // the helper selects this exact one once the display is online.
        s.hiDPI = 0;
        s.modes = @[[[modeClass alloc] initWithWidth:width height:height refreshRate:60.0]];
        if (!_screen || ![_screen applySettings:s]) {
            _screen = nil; if (error) *error = @"macOS rechazó la pantalla virtual."; return NO;
        }
        _layoutLock = [[NSLock alloc] init]; _layoutDirty = YES;
        _registeredLayout = CGDisplayRegisterReconfigurationCallback(ADLayoutChanged, (__bridge void *)self) == kCGErrorSuccess;
        [self restoreLayout];
        __weak ADVirtualScreen *weakSelf = self;
        _layoutTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
            ADVirtualScreen *screen = weakSelf; if (!screen) return;
            [screen->_layoutLock lock];
            if (screen->_layoutConfiguring) { [screen->_layoutLock unlock]; return; }
            BOOL changed = screen->_layoutDirty;
            BOOL topology = screen->_layoutTopologyDirty;
            screen->_layoutDirty = NO; screen->_layoutTopologyDirty = NO;
            if (changed) screen->_skipAbsentSave = topology;
            [screen->_layoutLock unlock];
            if (changed) [screen saveLayout];
        }];
        return YES;
    } @catch (NSException *exception) {
        _screen = nil;
        if (error) *error = @"La interfaz de pantalla virtual ha cambiado en este macOS.";
        return NO;
    }
}
- (void)markLayoutDirty:(CGDisplayChangeSummaryFlags)flags {
    [_layoutLock lock]; _layoutDirty = YES;
    if (flags & kCGDisplayBeginConfigurationFlag) {
        _layoutConfiguring = YES; _layoutTopologyDirty = NO;
        [_layoutLock unlock]; return;
    }
    _layoutConfiguring = NO;
    _layoutTopologyDirty |= (flags & (kCGDisplayAddFlag | kCGDisplayRemoveFlag | kCGDisplayEnabledFlag | kCGDisplayDisabledFlag)) != 0;
    [_layoutLock unlock];
}
- (BOOL)resizeWidth:(NSUInteger)width height:(NSUInteger)height error:(NSString **)error {
    [self destroy];
    return [self createWidth:width height:height error:error];
}
- (void)saveLayout {
    if (!_screen || !CGDisplayIsOnline(_screen.displayID)) return;
    CGDirectDisplayID online[64]; uint32_t count = 0; BOOL peer = NO;
    if (CGGetOnlineDisplayList(64, online, &count) == kCGErrorSuccess)
        for (uint32_t i = 0; i < count; ++i) if (online[i] != _screen.displayID && CGDisplayVendorNumber(online[i]) == 0xA1DE) peer = YES;
    if (peer) _hadPeer = YES;
    // A temporary disconnect can make macOS move the surviving monitor.
    // Keep its user placement until both return or a separate manual move.
    [_layoutLock lock]; BOOL topology = _skipAbsentSave || _layoutTopologyDirty; [_layoutLock unlock];
    if (_hadPeer && !peer && topology) return;
    CGRect r = CGDisplayBounds(_screen.displayID), main = CGDisplayBounds(CGMainDisplayID());
    if (CGRectIsEmpty(r) || CGRectIsEmpty(main) || _screen.displayID == CGMainDisplayID()) return;
    NSDictionary *layout = @{@"x": @(r.origin.x-main.origin.x), @"y": @(r.origin.y-main.origin.y),
        @"width": @(r.size.width), @"height": @(r.size.height), @"mainWidth": @(main.size.width), @"mainHeight": @(main.size.height)};
    [(_preferences ?: [NSUserDefaults standardUserDefaults]) setObject:layout forKey:ADLayoutKey(self.screenSlot)];
}
- (void)restoreLayout {
    NSDictionary *saved = [(_preferences ?: [NSUserDefaults standardUserDefaults]) dictionaryForKey:ADLayoutKey(self.screenSlot)];
    if (!_screen) return;
    if (!saved && self.screenSlot == 1) {
        CGRect main = CGDisplayBounds(CGMainDisplayID()), r = CGDisplayBounds(_screen.displayID);
        CGDirectDisplayID online[64]; uint32_t count = 0; double edge = main.origin.x;
        if (CGGetOnlineDisplayList(64, online, &count) == kCGErrorSuccess)
            for (uint32_t i = 0; i < count; ++i) if (online[i] != _screen.displayID) edge = MIN(edge, CGDisplayBounds(online[i]).origin.x);
        saved = @{@"x": @(edge - main.origin.x - r.size.width), @"y": @0, @"width": @(r.size.width), @"height": @(r.size.height), @"mainWidth": @(main.size.width), @"mainHeight": @(main.size.height)};
    }
    if (!saved) return;
    for (NSString *key in @[@"x", @"y", @"width", @"height", @"mainWidth", @"mainHeight"]) {
        if (![saved[key] isKindOfClass:[NSNumber class]] || !isfinite([saved[key] doubleValue])) return;
    }
    for (NSString *key in @[@"width", @"height", @"mainWidth", @"mainHeight"]) if ([saved[key] doubleValue] <= 0) return;
    CGRect r = CGDisplayBounds(_screen.displayID), main = CGDisplayBounds(CGMainDisplayID());
    if (CGRectIsEmpty(r) || CGRectIsEmpty(main)) return;
    double x = [saved[@"x"] doubleValue], y = [saved[@"y"] doubleValue];
    // Keep touching edges when either display changes resolution.
    if (x < 0) x += [saved[@"width"] doubleValue] - r.size.width;
    else if (x >= [saved[@"mainWidth"] doubleValue]) x += main.size.width - [saved[@"mainWidth"] doubleValue];
    if (y < 0) y += [saved[@"height"] doubleValue] - r.size.height;
    else if (y >= [saved[@"mainHeight"] doubleValue]) y += main.size.height - [saved[@"mainHeight"] doubleValue];
    x += main.origin.x; y += main.origin.y;
    if (fabs(x) > 100000 || fabs(y) > 100000) return;
    CGDisplayConfigRef config = NULL;
    if (CGBeginDisplayConfiguration(&config) != kCGErrorSuccess) return;
    // Apply both saved origins atomically. Moving just one screen can make
    // WindowServer rearrange the other one while an extension is recreated.
    BOOL valid = CGConfigureDisplayOrigin(config, _screen.displayID, (int32_t)round(x), (int32_t)round(y)) == kCGErrorSuccess;
    CGDirectDisplayID online[64]; uint32_t count = 0;
    if (valid && CGGetOnlineDisplayList(64, online, &count) == kCGErrorSuccess) {
        for (uint32_t i = 0; i < count; ++i) {
            CGDirectDisplayID other = online[i];
            if (other == _screen.displayID || CGDisplayVendorNumber(other) != 0xA1DE) continue;
            unsigned int product = CGDisplayModelNumber(other);
            if (product < 1 || product > 3) continue;
            NSDictionary *peer = [(_preferences ?: [NSUserDefaults standardUserDefaults]) dictionaryForKey:ADLayoutKey(product - 1)];
            BOOL complete = YES;
            for (NSString *key in @[@"x", @"y", @"width", @"height", @"mainWidth", @"mainHeight"])
                if (![peer[key] isKindOfClass:[NSNumber class]] || !isfinite([peer[key] doubleValue])) complete = NO;
            if (!complete) continue;
            CGRect bounds = CGDisplayBounds(other);
            if (CGRectIsEmpty(bounds) || [peer[@"width"] doubleValue] <= 0 || [peer[@"height"] doubleValue] <= 0 || [peer[@"mainWidth"] doubleValue] <= 0 || [peer[@"mainHeight"] doubleValue] <= 0) continue;
            double px = [peer[@"x"] doubleValue], py = [peer[@"y"] doubleValue];
            if (px < 0) px += [peer[@"width"] doubleValue] - bounds.size.width;
            else if (px >= [peer[@"mainWidth"] doubleValue]) px += main.size.width - [peer[@"mainWidth"] doubleValue];
            if (py < 0) py += [peer[@"height"] doubleValue] - bounds.size.height;
            else if (py >= [peer[@"mainHeight"] doubleValue]) py += main.size.height - [peer[@"mainHeight"] doubleValue];
            // A monitor to the left/above this one must follow its outer
            // edge when the middle monitor changes dimensions.
            if ([saved[@"x"] doubleValue] < 0 && fabs([peer[@"x"] doubleValue] + [peer[@"width"] doubleValue] - [saved[@"x"] doubleValue]) < 1)
                px += [saved[@"width"] doubleValue] - r.size.width;
            if ([saved[@"y"] doubleValue] < 0 && fabs([peer[@"y"] doubleValue] + [peer[@"height"] doubleValue] - [saved[@"y"] doubleValue]) < 1)
                py += [saved[@"height"] doubleValue] - r.size.height;
            px += main.origin.x; py += main.origin.y;
            if (fabs(px) > 100000 || fabs(py) > 100000) continue;
            valid = CGConfigureDisplayOrigin(config, other, (int32_t)round(px), (int32_t)round(py)) == kCGErrorSuccess;
            if (!valid) break;
        }
    }
    if (valid) CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
    else CGCancelDisplayConfiguration(config);
}
- (BOOL)startHelperWidth:(NSUInteger)width height:(NSUInteger)height error:(NSString **)error {
    // A display moved by CoreGraphics can survive object release on some macOS
    // versions. Isolate its lifetime so process exit reliably retires it.
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSBundle mainBundle].executableURL;
    NSString *domain = [NSBundle mainBundle].bundleIdentifier ?: [NSProcessInfo processInfo].processName;
    task.arguments = @[@"--virtual-display-helper", @(width).stringValue, @(height).stringValue, domain, @(self.screenSlot).stringValue];
    NSPipe *input = [NSPipe pipe], *output = [NSPipe pipe];
    task.standardInput = input; task.standardOutput = output; task.standardError = [NSFileHandle fileHandleWithNullDevice];
    dispatch_semaphore_t reply = dispatch_semaphore_create(0);
    NSLock *responseLock = [[NSLock alloc] init];
    NSMutableData *response = [[NSMutableData alloc] init];
    __block BOOL complete = NO;
    output.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *chunk = handle.availableData;
        [responseLock lock];
        if (!complete) {
            [response appendData:chunk];
            const void *newline = memchr(response.bytes, '\n', response.length);
            if (chunk.length == 0 || newline || response.length > 512) {
                complete = YES; dispatch_semaphore_signal(reply);
            }
        }
        [responseLock unlock];
    };
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        output.fileHandleForReading.readabilityHandler = nil;
        if (error) *error = @"No se pudo iniciar la pantalla virtual.";
        return NO;
    }
    BOOL answered = dispatch_semaphore_wait(reply, dispatch_time(DISPATCH_TIME_NOW, (int64_t)((self.startupTimeout > 0 ? self.startupTimeout : 10) * NSEC_PER_SEC))) == 0;
    output.fileHandleForReading.readabilityHandler = nil;
    [responseLock lock]; NSData *data = [response copy]; [responseLock unlock];
    NSString *raw = data.length <= 512 ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    NSString *line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    BOOL numeric = line.length > 0 && line.length <= 10 && [line rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location == NSNotFound;
    unsigned long long identifier = line.longLongValue;
    if (!answered || ![raw hasSuffix:@"\n"] || !numeric || identifier == 0 || identifier > UINT32_MAX || !task.running) {
        ADRetireHelper(task, input);
        if (error) *error = [line hasPrefix:@"ERROR:"] ? [line substringFromIndex:6] : @"No se pudo crear la pantalla virtual. Puedes duplicar la pantalla.";
        return NO;
    }
    _helper = task; _helperInput = input; _helperDisplayID = (CGDirectDisplayID)identifier;
    return YES;
}
+ (int)runHelper:(NSArray<NSString *> *)arguments {
    if (arguments.count != 5 && arguments.count != 6) return 2;
    NSUInteger slot = arguments.count == 6 ? arguments[5].integerValue : 0;
    if (slot > 2) return 2;
    NSUInteger width = arguments[2].integerValue, height = arguments[3].integerValue;
    // Remote screens are limited by the H.264 stream; the local HDMI desktop
    // is only scaled by WindowServer and can be larger (up to 5K).
    NSUInteger maxWidth = slot == 2 ? 5120 : 3840, maxHeight = slot == 2 ? 2880 : 2160;
    if (width < 320 || width > maxWidth || height < 200 || height > maxHeight) return 2;
    // One display owner per user, including diagnostic/duplicate app copies.
    NSString *leasePath = slot == 0 ? [NSString stringWithFormat:@"/private/tmp/prisondisplay-virtual-%u.lock", getuid()] : [NSString stringWithFormat:@"/private/tmp/prisondisplay-virtual-%u-%lu.lock", getuid(), (unsigned long)(slot + 1)];
    int lease = open(leasePath.fileSystemRepresentation, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600);
    struct stat info;
    if (lease < 0 || fstat(lease, &info) != 0 || !S_ISREG(info.st_mode) || info.st_uid != getuid() || flock(lease, LOCK_EX | LOCK_NB) != 0) {
        if (lease >= 0) close(lease);
        printf("ERROR:Ya hay otra pantalla de PRISON DISPLAY activa. Cierra la otra copia.\n"); fflush(stdout); return 1;
    }
    // Establish the display connection before allocating a new virtual monitor.
    // A failed/unresponsive session is cancelled by the parent's startup limit.
    if (CGMainDisplayID() == 0) { close(lease); printf("ERROR:La pantalla del Mac no está disponible.\n"); fflush(stdout); return 1; }
    CGDirectDisplayID displays[64]; uint32_t count = 0;
    if (CGGetOnlineDisplayList(64, displays, &count) != kCGErrorSuccess) { close(lease); return 1; }
    for (uint32_t i = 0; i < count; ++i) if (CGDisplayVendorNumber(displays[i]) == 0xA1DE && CGDisplayModelNumber(displays[i]) == 1 + slot) {
        close(lease); printf("ERROR:Ya hay una pantalla de PRISON DISPLAY activa. Cierra la otra copia.\n"); fflush(stdout); return 1;
    }
    // Quartz delivers external reconfiguration through the application's
    // event-processing thread. A Foundation-only loop can miss those events.
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    ADVirtualScreen *screen = [[ADVirtualScreen alloc] init];
    screen.screenSlot = slot;
    screen->_preferences = [[NSUserDefaults alloc] initWithSuiteName:arguments[4]];
    NSString *error = nil;
    if (![screen createWidth:width height:height error:&error]) { printf("ERROR:%s\n", (error ?: @"macOS no pudo crear la pantalla.").UTF8String); fflush(stdout); close(lease); return 1; }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!CGDisplayIsOnline(screen.displayID) && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    if (!CGDisplayIsOnline(screen.displayID)) { [screen destroy]; close(lease); printf("ERROR:La pantalla virtual no quedó disponible.\n"); fflush(stdout); return 1; }
    int selected = ADSelectExactMode(screen.displayID, width, height);
    deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (selected == 1 && (CGDisplayPixelsWide(screen.displayID) != width || CGDisplayPixelsHigh(screen.displayID) != height) && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    if (CGDisplayPixelsWide(screen.displayID) != width || CGDisplayPixelsHigh(screen.displayID) != height) {
        [screen destroy]; close(lease); printf("ERROR:macOS no activó %lu × %lu en la pantalla virtual. Prueba un tamaño menor.\n", (unsigned long)width, (unsigned long)height); fflush(stdout); return 1;
    }
    // The size changed after the saved arrangement was applied; re-anchor it.
    // Untouched displays keep the single arrangement transaction of creation.
    if (selected == 1) [screen restoreLayout];
    printf("%u\n", screen.displayID); fflush(stdout);
    NSLock *lock = [[NSLock alloc] init]; __block BOOL alive = YES;
    NSFileHandle *input = [NSFileHandle fileHandleWithStandardInput];
    input.readabilityHandler = ^(NSFileHandle *handle) {
        if (handle.availableData.length == 0) { [lock lock]; alive = NO; [lock unlock]; }
    };
    while (YES) {
        [lock lock]; BOOL running = alive; [lock unlock]; if (!running) break;
        @autoreleasepool {
            NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05] inMode:NSDefaultRunLoopMode dequeue:YES];
            if (event) [NSApp sendEvent:event];
        }
    }
    input.readabilityHandler = nil;
    [screen destroy]; [screen->_preferences synchronize]; close(lease);
    return 0;
}
- (void)destroy {
    if (_helper) {
        NSTask *task = _helper;
        _helper = nil; _helperDisplayID = 0;
        NSPipe *input = _helperInput; _helperInput = nil;
        ADRetireHelper(task, input);
    }
    [_layoutTimer invalidate]; _layoutTimer = nil;
    if (_registeredLayout) { CGDisplayRemoveReconfigurationCallback(ADLayoutChanged, (__bridge void *)self); _registeredLayout = NO; }
    [self saveLayout]; _screen = nil;
}
- (void)dealloc {
    [_layoutTimer invalidate];
    if (_registeredLayout) CGDisplayRemoveReconfigurationCallback(ADLayoutChanged, (__bridge void *)self);
    [_helperInput.fileHandleForWriting closeFile];
    if (_helper.running) kill(_helper.processIdentifier, SIGKILL);
}
@end

#import <dlfcn.h>
#import <math.h>
@implementation ADBrightness
+ (CGDirectDisplayID)physicalPanel {
    CGDirectDisplayID displays[32]; uint32_t count = 0;
    if (CGGetOnlineDisplayList(32, displays, &count) != kCGErrorSuccess) return 0;
    for (uint32_t i = 0; i < count; i++) {
        if (CGDisplayVendorNumber(displays[i]) != 0xA1DE && CGDisplayIsBuiltin(displays[i])) return displays[i];
    }
    return 0;
}
+ (void *)services {
    static void *library; static dispatch_once_t once;
    dispatch_once(&once, ^{ library = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY | RTLD_LOCAL); });
    return library;
}
+ (double)read {
    void *library = [self services]; CGDirectDisplayID panel = [self physicalPanel];
    if (!library || !panel) return -1;
    int (*get)(CGDirectDisplayID, float *) = dlsym(library, "DisplayServicesGetBrightness");
    float value = 0;
    if (!get || get(panel, &value) != 0 || !isfinite(value) || value < 0 || value > 1) return -1;
    return value;
}
+ (double)apply:(double)level {
    if (!isfinite(level) || level < 0.05 || level > 1) return -1;
    void *library = [self services]; CGDirectDisplayID panel = [self physicalPanel];
    if (!library || !panel) return -1;
    int (*set)(CGDirectDisplayID, float) = dlsym(library, "DisplayServicesSetBrightness");
    if (!set || set(panel, (float)level) != 0) return -1;
    return [self read];
}
@end
