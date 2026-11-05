import AppKit
#if SENDER || UNIFIED
if CommandLine.arguments.contains("--virtual-display-helper") { exit(ADVirtualScreen.runHelper(CommandLine.arguments)) }
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
let app = NSApplication.shared
#if UNIFIED
let controller = PrisonWorkspaceController()
#else
let controller = AppController()
#endif
app.delegate = controller
app.run()
