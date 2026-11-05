import AppKit
import Darwin
setbuf(stdout, nil)
if CommandLine.arguments.contains("--virtual-display-helper") {
    // Fault injection is confined to this test executable, not the apps.
    switch ProcessInfo.processInfo.environment["PRISON_TEST_HELPER_MODE"] {
    case "hang":
        signal(SIGTERM, SIG_IGN)
        while true { Thread.sleep(forTimeInterval: 0.05) }
    case "partial":
        print("100", terminator: ""); fflush(stdout); Thread.sleep(forTimeInterval: 0.08)
        print("9"); fflush(stdout)
        while !FileHandle.standardInput.availableData.isEmpty {}
        exit(0)
    case "invalid": print("123invalid"); fflush(stdout); Thread.sleep(forTimeInterval: 1); exit(0)
    default: Thread.sleep(forTimeInterval: 0.2); exit(ADVirtualScreen.runHelper(CommandLine.arguments))
    }
}
CGDisplayRegisterReconfigurationCallback({ _, _, _ in }, nil)
func pump(_ condition: () -> Bool, timeout: Double = 5) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { autoreleasepool { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) } }
    return condition()
}
func displays() -> [UInt32] {
    var count: UInt32 = 0; CGGetOnlineDisplayList(0, nil, &count)
    var result = [UInt32](repeating: 0, count: Int(count)); CGGetOnlineDisplayList(count, &result, &count); return result
}
var failures = 0
func check(_ condition: Bool, _ name: String) { print(condition ? "PASS: \(name)" : "FAIL: \(name)"); if !condition { failures += 1 } }
let before = displays(); let main = CGMainDisplayID()
let v = ADVirtualScreen(); var message: NSString?
setenv("PRISON_TEST_HELPER_MODE", "hang", 1)
v.startupTimeout = 0.05
let hangStart = ProcessInfo.processInfo.systemUptime
check(!v.createWidth(1280, height: 720, error: &message), "unresponsive helper rejected")
check(ProcessInfo.processInfo.systemUptime - hangStart < 2.5, "helper ignoring termination cannot block indefinitely")
setenv("PRISON_TEST_HELPER_MODE", "partial", 1)
v.startupTimeout = 2
check(v.createWidth(1280, height: 720, error: &message) && v.displayID == 1009, "fragmented startup identifier waits for the complete line")
v.destroy()
setenv("PRISON_TEST_HELPER_MODE", "invalid", 1)
check(!v.createWidth(1280, height: 720, error: &message), "invalid startup identifier rejected")
unsetenv("PRISON_TEST_HELPER_MODE")
v.startupTimeout = 0.02
check(!autoreleasepool { v.createWidth(1280, height: 720, error: &message) }, "slow helper startup times out safely")
check(pump({ displays().sorted() == before.sorted() }), "startup timeout retires partial virtual display")
v.startupTimeout = 0
check(autoreleasepool { v.createWidth(1920, height: 1080, error: &message) }, "virtual display created")
let id = v.displayID
let uuid = CGDisplayCreateUUIDFromDisplayID(id).takeRetainedValue()
let firstIdentity = CFUUIDCreateString(nil, uuid) as String
check(pump({ displays().contains(id) && CGDisplayPixelsWide(id) == 1920 }), "virtual display has selected mode")
let duplicate = ADVirtualScreen(); var duplicateError: NSString?
check(!duplicate.createWidth(1280, height: 720, error: &duplicateError) && duplicate.displayID == 0, "second app copy cannot create a competing virtual screen")
let leftEdge = before.map { CGDisplayBounds($0).minX }.min() ?? 0
let expected = CGPoint(x: leftEdge - 1920, y: 80)
var config: CGDisplayConfigRef?
check(CGBeginDisplayConfiguration(&config) == .success, "arrangement transaction begins")
check(CGConfigureDisplayOrigin(config, id, Int32(expected.x), 80) == .success, "left display position requested")
check(CGCompleteDisplayConfiguration(config, .forSession) == .success, "arrangement transaction completes")
check(pump({ CGDisplayBounds(id).origin == expected }), "arrangement applied")
autoreleasepool { v.destroy() }
check(pump({ !displays().contains(id) }), "virtual display removed")
check(autoreleasepool { v.createWidth(1920, height: 1080, error: &message) }, "virtual display recreated")
let recreatedUUID = CGDisplayCreateUUIDFromDisplayID(v.displayID).takeRetainedValue()
check((CFUUIDCreateString(nil, recreatedUUID) as String) == firstIdentity, "recreating a resolution reuses its ColorSync identity")
check(pump({ CGDisplayBounds(v.displayID).origin == expected }), "saved position restored after recreation")
check(autoreleasepool { v.resizeWidth(1280, height: 720, error: &message) }, "existing display resized")
check(pump({ CGDisplayPixelsWide(v.displayID) == 1280 }), "new resolution active")
check(pump({ CGDisplayBounds(v.displayID).origin == CGPoint(x: leftEdge - 1280, y: 80) }), "left edge stays adjacent after resize")
check(main == CGMainDisplayID(), "main display unchanged")
autoreleasepool { v.destroy() }
check(pump({ displays() == before }), "original display set restored")
print("RESULT: \(failures) failures")
exit(failures == 0 ? 0 : 1)
