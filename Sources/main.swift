import AppKit
#if SENDER || UNIFIED
if CommandLine.arguments.contains("--virtual-display-helper") { exit(ADVirtualScreen.runHelper(CommandLine.arguments)) }
// Verification of a real update with this signed app: install the zip into a
// copy of this app (never into /Applications) and report, without relaunching.
if let index = CommandLine.arguments.firstIndex(of: "--update-self-test"), CommandLine.arguments.count > index + 2 {
    do { let app = try AppUpdater.install(URL(fileURLWithPath: CommandLine.arguments[index + 1]), version: CommandLine.arguments[index + 2]); print("INSTALLED", app.path); exit(0) }
    catch { print("REFUSED", error); exit(1) }
}
if CommandLine.arguments.contains("--diagnostic-screen-permission") {
    print("screen-preflight=\(ScreenCaptureAccess.permitted())")
    exit(0)
}

// Read-only diagnostic for the installed app's real TCC identity. It never
// requests permission, captures a screen or posts input events.
if CommandLine.arguments.contains("--diagnostic-input-permission") {
    var allowed = true
    let times = (0..<500).map { _ -> Double in
        let start = monotonicNS(); allowed = AXIsProcessTrusted() && allowed
        return Double(monotonicNS()-start)/1000
    }.sorted()
    print("PERMISSION DIAGNOSTIC version=\(AppVersion.current) allowed=\(allowed) samples=\(times.count) medianUS=\(times[times.count/2]) p95US=\(times[times.count*95/100]) maxUS=\(times.last!)")
    exit(allowed ? 0 : 2)
}
#endif
// An older copy registered to open at login from another folder (for example
// a build directory) would advertise the same screens with another version.
// Keep only this copy; its helper processes live inside the same bundle.
if let identifier = Bundle.main.bundleIdentifier, !CommandLine.arguments.contains("--layout-preview") {
    let own = Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath()
    for other in NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
    where other.processIdentifier != getpid() && other.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() != own {
        other.terminate()
    }
}
#if UNIFIED && !LEGACY
// Real check of the corrected-monitor compositor on the connected monitor.
if let index = CommandLine.arguments.firstIndex(of: "--correction-self-test") {
    let folder = CommandLine.arguments.count > index + 1 ? URL(fileURLWithPath: CommandLine.arguments[index + 1]) : FileManager.default.temporaryDirectory.appendingPathComponent("PrisonCorrection")
    if #available(macOS 14.0, *) { CorrectionSelfTest.run(folder: folder) }
    print("Necesita macOS 14 o posterior"); exit(2)
}
#endif
let app = NSApplication.shared
#if UNIFIED
let controller = PrisonWorkspaceController()
#else
let controller = AppController()
#endif
app.delegate = controller
app.run()
