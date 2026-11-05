import AppKit
import Darwin
setbuf(stdout, nil)
if CommandLine.arguments.contains("--position-test-display") {
    var transaction: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&transaction) == .success else { exit(1) }
    let id = UInt32(CommandLine.arguments[2])!
    guard CGConfigureDisplayOrigin(transaction,id,Int32(CommandLine.arguments[3])!,Int32(CommandLine.arguments[4])!) == .success else { CGCancelDisplayConfiguration(transaction); exit(1) }
    if CommandLine.arguments.count == 8 {
        guard CGConfigureDisplayOrigin(transaction,UInt32(CommandLine.arguments[5])!,Int32(CommandLine.arguments[6])!,Int32(CommandLine.arguments[7])!) == .success else { CGCancelDisplayConfiguration(transaction); exit(1) }
    }
    exit(CGCompleteDisplayConfiguration(transaction,.forSession) == .success ? 0 : 1)
}
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
let second = ADVirtualScreen(); second.screenSlot = 1
var secondError: NSString?
check(second.createWidth(1920, height: 1080, error: &secondError), "second receiver creates its own simultaneous display")
let secondID = second.displayID
print("DISPLAY IDS", id, secondID, displays())
check(secondID != id && displays().contains(secondID) && displays().contains(id), "both independent monitors are online")
let secondUUID = CGDisplayCreateUUIDFromDisplayID(secondID).takeRetainedValue()
check((CFUUIDCreateString(nil, secondUUID) as String) != firstIdentity, "same resolution has distinct monitor identities")
let duplicateSecond = ADVirtualScreen(); duplicateSecond.screenSlot = 1
check(!duplicateSecond.createWidth(1280, height: 720, error: &secondError), "duplicate second slot remains protected")
let mainBounds = CGDisplayBounds(main)
for (key, x) in [("PrisonDisplay.layout", -3840), ("PrisonDisplay.layout.2", -1920)] {
    UserDefaults.standard.set(["x":x,"y":0,"width":1920,"height":1080,"mainWidth":Int(mainBounds.width),"mainHeight":Int(mainBounds.height)], forKey:key)
}
UserDefaults.standard.synchronize()
let joint = Process(); joint.executableURL = Bundle.main.executableURL
joint.arguments = ["--position-test-display",String(id),"-3840","100",String(secondID),"-1920","100"]
try joint.run(); joint.waitUntilExit()
check(joint.terminationStatus == 0 && pump({CGDisplayBounds(id).minX == -3840 && CGDisplayBounds(secondID).minX == -1920}),"three-screen order applied atomically")
func savedY(_ key: String) -> Int? {
    let command = Process(); command.executableURL = URL(fileURLWithPath:"/usr/bin/defaults")
    command.arguments = ["read",ProcessInfo.processInfo.processName,key]
    let output = Pipe(); command.standardOutput = output; command.standardError = FileHandle.nullDevice
    do { try command.run(); command.waitUntilExit()
        guard command.terminationStatus == 0 else { return nil }
        let plist = try PropertyListSerialization.propertyList(from:output.fileHandleForReading.readDataToEndOfFile(),options:[],format:nil) as? [String:Any]
        if let number = plist?["y"] as? NSNumber { return number.intValue }
        return (plist?["y"] as? String).flatMap(Int.init)
    } catch { return nil }
}
check(pump({savedY("PrisonDisplay.layout") == 100 && savedY("PrisonDisplay.layout.2") == 100}),"both helper processes persist an external arrangement while streaming")
check(second.resizeWidth(1280, height: 720, error: &secondError), "second monitor changes resolution independently")
check(pump({CGDisplayBounds(id).minX == -3200 && CGDisplayBounds(second.displayID).minX == -1280}),"resizing middle screen preserves Pro-iMac-Air adjacency and order")
print("RESIZED GEOMETRY",CGDisplayBounds(id),CGDisplayBounds(second.displayID),"SAVED Y",savedY("PrisonDisplay.layout") as Any,savedY("PrisonDisplay.layout.2") as Any)
check(displays().contains(id) && CGDisplayPixelsWide(id) == 1920, "changing second monitor preserves first monitor")
second.destroy()
check(pump({ !displays().contains(secondID) && displays().contains(id) }), "disconnecting second monitor preserves first monitor")
let leftEdge = before.map { CGDisplayBounds($0).minX }.min() ?? 0
let expected = CGPoint(x: leftEdge - 1920, y: 80)
// A CoreGraphics configuration holds a display lease in the configuring
// process on current macOS. Use a short-lived owner just like System Settings.
let positioner = Process(); positioner.executableURL = Bundle.main.executableURL
positioner.arguments = ["--position-test-display",String(id),String(Int(expected.x)),"80"]
try positioner.run(); positioner.waitUntilExit()
check(positioner.terminationStatus == 0,"external arrangement transaction completes")
check(pump({ CGDisplayBounds(id).origin == expected && savedY("PrisonDisplay.layout") == 80 }), "manual arrangement is applied and persisted after the other screen disconnects")
autoreleasepool { v.destroy() }
check(pump({ !displays().contains(id) }, timeout: 12), "virtual display removed")
print("AFTER REMOVAL",displays())
check(autoreleasepool { v.createWidth(1920, height: 1080, error: &message) }, "virtual display recreated")
check(pump({ displays().contains(v.displayID) && CGDisplayIsOnline(v.displayID) != 0 }), "recreated monitor is online")
if let recreatedUUID = CGDisplayCreateUUIDFromDisplayID(v.displayID)?.takeRetainedValue() {
check((CFUUIDCreateString(nil, recreatedUUID) as String) == firstIdentity, "recreating a resolution reuses its ColorSync identity")
} else { check(false,"recreated monitor exposes its identity") }
check(pump({ CGDisplayBounds(v.displayID).origin == expected }), "saved position restored after recreation")
check(autoreleasepool { v.resizeWidth(1280, height: 720, error: &message) }, "existing display resized")
check(pump({ CGDisplayPixelsWide(v.displayID) == 1280 }), "new resolution active")
check(pump({ CGDisplayBounds(v.displayID).origin == CGPoint(x: leftEdge - 1280, y: 80) }), "left edge stays adjacent after resize")
check(main == CGMainDisplayID(), "main display unchanged")
autoreleasepool { v.destroy() }
check(pump({ displays() == before }), "original display set restored")
print("RESULT: \(failures) failures")
exit(failures == 0 ? 0 : 1)
