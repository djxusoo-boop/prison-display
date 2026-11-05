import AppKit
import Darwin
#if !LEGACY
import Network
#endif
setbuf(stdout, nil)
if let path = CommandLine.arguments.first(where: { $0.hasPrefix("log=") })?.dropFirst(4) {
    umask(0o077); _ = freopen(String(path), "w", stdout); _ = freopen(String(path)+".errors", "w", stderr)
}
let output = CommandLine.arguments.first(where: { $0.hasPrefix("output=") }).map { String($0.dropFirst(7)) } ?? "build"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
var checks = 0, failures = 0
func check(_ result: Bool, _ title: String) { checks += 1; if !result { failures += 1; print("FAIL", title) } }
@discardableResult func pump(until condition: () -> Bool, timeout: Double = 4) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    return condition()
}
func drainMain() { var drained = false; DispatchQueue.main.async { drained = true }; _ = pump(until: { drained }) }
if CommandLine.arguments.contains("--names-only") {
    let defaults = UserDefaults(suiteName: "PrisonDisplay.workspace.names.\(UUID().uuidString)")!
    check(WorkspaceScreenNames.label(slot: 0, defaults: defaults) == "Pantalla 1" && WorkspaceScreenNames.label(slot: 1, defaults: defaults) == "Pantalla 2", "first connection keeps the two default screen labels")
    WorkspaceScreenNames.remember("  iMac de Xuso  ", slot: 0, defaults: defaults)
    check(WorkspaceScreenNames.label(slot: 0, defaults: defaults) == "iMac de Xuso" && WorkspaceScreenNames.label(slot: 1, defaults: defaults) == "Pantalla 2", "each screen retains its own connected Mac name")
    check(WorkspaceScreenNames.buttonTitle(slot: 0, defaults: defaults) == "↗  iMac de Xuso", "remembered name replaces the numeric button label")
    WorkspaceScreenNames.remember("", slot: 1, defaults: defaults)
    check(WorkspaceScreenNames.name(slot: 1, defaults: defaults) == nil, "empty peer name does not overwrite the initial label")
    print("RESULT", checks, "checks", failures, "failures")
    exit(failures == 0 ? 0 : 1)
}
let app = NSApplication.shared
let isolated = UserDefaults(suiteName: "PrisonDisplay.workspace.fixture.\(UUID().uuidString)")!
check(WorkspaceScreenNames.label(slot: 0, defaults: isolated) == "Pantalla 1" && WorkspaceScreenNames.label(slot: 1, defaults: isolated) == "Pantalla 2", "unpaired screen slots keep their first-use labels")
WorkspaceScreenNames.remember("  iMac de Xuso  ", slot: 0, defaults: isolated)
check(WorkspaceScreenNames.label(slot: 0, defaults: isolated) == "iMac de Xuso" && WorkspaceScreenNames.label(slot: 1, defaults: isolated) == "Pantalla 2", "each slot remembers its own peer name")
check(WorkspaceScreenNames.buttonTitle(slot: 0, defaults: isolated) == "↗  iMac de Xuso", "known peer name replaces the numeric button label")
WorkspaceScreenNames.remember("", slot: 1, defaults: isolated)
check(WorkspaceScreenNames.name(slot: 1, defaults: isolated) == nil, "empty peer names do not replace the first-use label")
check(ScreenRole.initial(defaults: isolated, senderIdentity: true) == .send, "old sender keeps sending as its default")
check(ScreenRole.initial(defaults: isolated, senderIdentity: false) == .receive, "old receiver keeps receiving as its default")
isolated.set("receive", forKey: "PrisonDisplay.workspace.role")
check(ScreenRole.initial(defaults: isolated, senderIdentity: true) == .receive, "saved role overrides distribution default")
check(ScreenRole.send.trustAccount(identifier: "local.airedisplay.Sender", senderIdentity: true) == "local.airedisplay.Sender", "existing sender Keychain account preserved")
check(ScreenRole.receive.trustAccount(identifier: "local.airedisplay.Receiver", senderIdentity: false) == "local.airedisplay.Receiver", "existing receiver Keychain account preserved")
check(ScreenRole.receive.trustAccount(identifier: "local.airedisplay.Sender", senderIdentity: true) != "local.airedisplay.Receiver", "switching roles never adopts the other app's Keychain identity")
isolated.removeObject(forKey: "PrisonDisplay.workspace.role")
isolated.set(true, forKey: "PrisonDisplay.workspace.secondScreen")
let controller = PrisonWorkspaceController(defaults: isolated, identifier: "local.airedisplay.Sender")
// Layout tests never read the user's production connections or request Keychain access.
controller.sender.loadRememberedConnection = { _ in nil }
controller.secondSender.loadRememberedConnection = { _ in nil }
controller.receiver.loadRememberedConnection = { _ in nil }
controller.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
check(controller.versionButton.title == "PRISON DISPLAY · v\(AppVersion.current)" && controller.versionButton.target === controller && controller.versionButton.action == #selector(PrisonWorkspaceController.footerAction), "version footer is a clickable full-screen shortcut")
check(controller.fullscreenReceiversButton.title == "Pantalla completa en conectados" && !controller.fullscreenReceiversButton.isHidden && !controller.fullscreenReceiversButton.isEnabled, "sender shows the fullscreen action and disables it only when no receiver is streaming")
check(PrisonWorkspaceController.fullscreenTargets(first: .streaming, second: .available, secondEnabled: true) == [0], "fullscreen targets the connected first screen while the second is unavailable")
check(PrisonWorkspaceController.fullscreenTargets(first: .available, second: .streaming, secondEnabled: true) == [1], "fullscreen targets the connected second screen while the first is unavailable")
check(PrisonWorkspaceController.fullscreenTargets(first: .streaming, second: .streaming, secondEnabled: true) == [0, 1], "fullscreen targets both connected screens")
check(PrisonWorkspaceController.fullscreenTargets(first: .streaming, second: .streaming, secondEnabled: false) == [0], "fullscreen never targets a disabled second screen")
check(controller.sender.hosted && controller.receiver.hosted, "both panels use the same window")
check(!controller.sender.workspaceActive && !controller.receiver.workspaceActive, "preview starts no network workflow")
check(!controller.sender.expertMode && !controller.secondSender.expertMode && !controller.receiver.expertMode, "simple mode is the default in all panels")
controller.setExpertMode(true)
check(controller.sender.expertMode && controller.secondSender.expertMode && controller.receiver.expertMode, "expert mode applies to all panels")
check(!controller.sender.workspaceActive && !controller.receiver.workspaceActive, "expert toggle does not connect or change role")
controller.setExpertMode(false)
func visibleText(_ view: NSView) -> [String] {
    guard !view.isHidden else { return [] }
    return (view as? NSTextField).map { [$0.stringValue] } ?? view.subviews.flatMap(visibleText)
}
// Deterministic discovery regressions: duplicates, disappearing devices,
// stale controls, non-service endpoints and connection-state buttons.
controller.select(.receive)
let peerOne = NWEndpoint.service(name: "MacBook Air · Pantalla 1", type: PairingServer.service, domain: "local.", interface: nil)
let peerTwo = NWEndpoint.service(name: "iMac · Pantalla 2", type: PairingServer.service, domain: "local.", interface: nil)
controller.receiver.updateDiscoveredDevices([peerTwo, peerOne, peerOne, .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: 55000)!)])
check(controller.receiver.endpoints.count == 2, "discovery deduplicates and excludes non-service endpoints")
func allButtons(_ view: NSView) -> [NSButton] { (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(allButtons) }
let oldButtons = allButtons(controller.receiver.deviceList)
check(oldButtons.filter { $0.title == "Conectar" && $0.isEnabled }.count == 2, "each available Mac has an enabled one-click connection button")
controller.receiver.devices.selectItem(at: controller.receiver.endpoints.firstIndex(of: peerTwo)!)
controller.receiver.updateDiscoveredDevices([peerTwo])
check(controller.receiver.endpoints[controller.receiver.devices.indexOfSelectedItem] == peerTwo, "selected endpoint survives updates")
for button in oldButtons { controller.receiver.connectDevice(button) }
check(controller.receiver.browser == nil, "removed buttons cannot start a different connection")
controller.receiver.displayPhase(.connecting)
check(allButtons(controller.receiver.deviceList).allSatisfy { !$0.isEnabled }, "connection in progress disables duplicate requests")
controller.receiver.displayPhase(.idle)
controller.receiver.updateDiscoveredDevices([])
check(visibleText(controller.receiver.deviceList).contains(where: { $0.contains("No hay Mac disponibles") }), "empty discovery explains how to make the other Mac available")
controller.receiver.updateDiscoveredDevices([peerOne, peerTwo])
let fixtureProfile = try TrustedProfile(ConnectionLink(host: "Mac-de-prueba.local", port: 55001, key: newPairingKey(), serviceName: "Prison-fixture"))
let accessLock = NSLock()
var accessRequests: [Bool] = []
controller.receiver.loadRememberedConnection = { interactive in
    accessLock.lock(); accessRequests.append(interactive); accessLock.unlock()
    if !interactive { throw AireError("Fixture: macOS requiere autorización") }
    return fixtureProfile
}
controller.receiver.readRememberedConnection()
let recoveryDeadline = Date().addingTimeInterval(2)
while !visibleText(controller.receiver.deviceList).contains(where: { $0.contains("Enlazado") }) && Date() < recoveryDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
accessLock.lock(); let automaticAccess = accessRequests; accessLock.unlock()
check(automaticAccess == [false, true], "denied silent recovery retries once with normal Keychain authorization")
check(controller.receiver.recoverConnection.isHidden, "successful automatic authorization hides manual recovery")
let readDeadline = Date().addingTimeInterval(2)
while !visibleText(controller.receiver.deviceList).contains(where: { $0.contains("Enlazado") }) && Date() < readDeadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
}
check(visibleText(controller.receiver.deviceList).contains("Mac-de-prueba · Enlazado"), "saved Mac appears separately without exposing credentials")
check(allButtons(controller.receiver.deviceList).contains(where: { $0.title == "Conectar de nuevo" && $0.isEnabled }), "remembered connection has its own one-click recovery")
controller.receiver.readRememberedConnection()
accessLock.lock(); let explicitAccess = accessRequests; accessLock.unlock()
check(explicitAccess == [false, true], "automatic recovery reuses the approved Keychain profile without another read")
var requests: [NWEndpoint] = []
controller.receiver.requestDeviceConnection = { requests.append($0) }
let liveButtons = allButtons(controller.receiver.deviceList).filter { $0.title == "Conectar" }
controller.receiver.connectDevice(liveButtons[0])
check(requests.count == 1 && requests[0] == peerOne, "one click requests exactly the displayed computer")
let retiredConnected = controller.receiver.pairing.onConnected
let retiredEnded = controller.receiver.pairing.onEnded
let retiredStatus = controller.receiver.pairing.onStatus
let retiredConfirm = controller.receiver.pairing.onConfirm
controller.receiver.connectDevice(liveButtons[0])
check(requests.count == 1, "double click cannot send a duplicate pairing request")
controller.receiver.displayPhase(.idle)
controller.receiver.updateDiscoveredDevices([peerTwo])
let nextButton = allButtons(controller.receiver.deviceList).first { $0.title == "Conectar" }!
controller.receiver.connectDevice(nextButton)
check(requests.count == 2 && requests[1] == peerTwo, "a new attempt selects the second computer")
controller.receiver.status.stringValue = "Solicitud actual"
var retiredRejected = false
retiredConnected?(try fixtureProfile.link()); retiredEnded?(); retiredStatus?("Error antiguo")
retiredConfirm?("Mac antiguo", "123456") { accepted in retiredRejected = !accepted }
_ = pump(until: { retiredRejected }); drainMain()
check(controller.receiver.viewer == nil, "old attempt cannot open a viewer during a new attempt")
check(controller.receiver.status.stringValue != "Error antiguo", "old attempt cannot overwrite the new status")
check(retiredRejected, "old attempt is rejected before displaying a confirmation")
controller.receiver.stop()
RunLoop.current.run(until: Date().addingTimeInterval(0.15))
controller.receiver.requestDeviceConnection = nil
check(controller.receiver.browser == nil, "isolated UI diagnostics never start real discovery")
var searches: [NWBrowser] = []
controller.receiver.startDiscovery = { searches.append($0) }
controller.receiver.discoveryRetryDelay = 0.03
controller.receiver.browse()
check(searches.count == 1, "search starts exactly once")
let retiredSearch = searches[0]
#if LEGACY
let searchError = NWError("Fixture: sin red")
#else
let searchError = NWError.posix(.ENETDOWN)
#endif
if #available(macOS 11.0, *) {
    retiredSearch.stateUpdateHandler?(.waiting(searchError))
    RunLoop.current.run(until: Date().addingTimeInterval(0.03))
    check(visibleText(controller.receiver.deviceList).contains(where: { $0.contains("Esperando a la red") }), "waiting network is distinguished from an empty computer list")
}
retiredSearch.stateUpdateHandler?(.failed(searchError))
_ = pump(until: { searches.count >= 2 })
check(searches.count == 2, "failed browser is replaced instead of blocking future search (count=\(searches.count))")
retiredSearch.stateUpdateHandler?(.failed(searchError))
drainMain()
check(searches.count == 2, "a retired browser cannot schedule another search")
searches.last?.stateUpdateHandler?(.failed(searchError))
controller.receiver.deactivateWorkspace()
RunLoop.current.run(until: Date().addingTimeInterval(0.1))
check(searches.count == 2 && controller.receiver.browser == nil, "leaving receiver cancels a pending discovery retry")
controller.receiver.startDiscovery = nil
controller.receiver.activateWorkspace()

controller.receiver.updateDiscoveredDevices([peerOne, peerTwo])
func inspect(_ view: NSView) {
    if view.isHidden { return }
    if let field = view as? NSTextField, !field.stringValue.isEmpty {
        check(field.frame.width > 0 && field.frame.height > 0, "visible text has a nonzero frame")
        check(field.frame.height + 1 >= field.fittingSize.height, "text is not vertically compressed: \(field.stringValue)")
    }
    if let stack = view as? NSStackView, stack.orientation == .vertical {
        let visible = stack.arrangedSubviews.filter { !$0.isHidden }
        for (before, after) in zip(visible, visible.dropFirst()) {
            check(after.frame.minY >= before.frame.maxY-1, "vertical controls do not overlap")
        }
    }
    for child in view.subviews { inspect(child) }
}
for expert in [false, true] {
controller.setExpertMode(expert)
for role in [ScreenRole.receive, .send, .receive] {
    controller.select(role)
    check(controller.role == role, "chosen direction is visible")
    check(controller.sender.workspaceActive == (role == .send) && controller.receiver.workspaceActive == (role == .receive), "only the selected workflow stays active")
    check(controller.heading.stringValue == role.title, "header agrees with selected direction")
    let labels = visibleText(controller.window.contentView!)
    check(labels.contains(role == .send ? "Resolución" : "Posición") == expert, "advanced settings appear only in expert mode")
    let savedResolution = controller.sender.resolution.indexOfSelectedItem
    controller.setExpertMode(!expert); controller.setExpertMode(expert)
    check(controller.sender.resolution.indexOfSelectedItem == savedResolution, "expert toggle preserves image settings")
    check(controller.sender.workspaceActive == (role == .send) && controller.receiver.workspaceActive == (role == .receive), "expert toggle preserves active workflow")
    for width: CGFloat in [860, 980, 1200] {
        controller.window.setContentSize(NSSize(width: width, height: 760))
        controller.window.contentView?.layoutSubtreeIfNeeded()
        for panel in controller.container.subviews {
            if let scroll = panel.subviews.first as? NSScrollView, let root = scroll.documentView as? NSStackView {
                root.setFrameSize(NSSize(width: width-228, height: root.fittingSize.height)); root.layoutSubtreeIfNeeded()
            }
        }
        controller.window.contentView?.layoutSubtreeIfNeeded()
        inspect(controller.window.contentView!)
    }
    controller.window.setContentSize(NSSize(width: 980, height: 850)); controller.window.contentView?.layoutSubtreeIfNeeded()
    if let view = controller.window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output+"/Workspace-\(role.rawValue)-\(expert ? "expert" : "simple").png"))
    }
}
}
controller.select(.send)
controller.chooseSecondSend()
check(controller.selectedScreen == 1 && controller.sender.workspaceActive && controller.secondSender.workspaceActive, "second screen leaves first sender active")
check(controller.secondSender.screenSlot == 1 && controller.sender.screenSlot == 0, "senders have separate monitor slots")
controller.chooseSend()
check(controller.selectedScreen == 0 && controller.secondSender.workspaceActive, "switching screen settings leaves second sender active")
controller.select(.receive)
controller.footerAction()
check(controller.receiver.viewer == nil && controller.receiver.status.stringValue.contains("Conecta un Mac"), "full-screen shortcut explains when no received image is available")
controller.receiver.showViewer()
guard let receivedViewer = controller.receiver.viewer else { fatalError("missing receiver viewer") }
controller.receiver.windowDidEnterFullScreen(Notification(name: NSWindow.didEnterFullScreenNotification, object: receivedViewer))
check(controller.receiver.video.videoLayer.videoGravity == .resizeAspectFill, "full-screen viewer fills the display without distorting the image")
controller.receiver.windowDidExitFullScreen(Notification(name: NSWindow.didExitFullScreenNotification, object: receivedViewer))
check(controller.receiver.video.videoLayer.videoGravity == .resizeAspect, "windowed viewer returns to the full image without cropping")
receivedViewer.close()
check(!controller.sender.workspaceActive && !controller.secondSender.workspaceActive, "receiving stops both sender workflows")
controller.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
check(!controller.sender.workspaceActive && !controller.secondSender.workspaceActive && !controller.receiver.workspaceActive, "closing releases both workflows")
controller.receiver.connect(try fixtureProfile.link(), previouslyApproved: true)
check(controller.receiver.viewer?.isVisible != true, "inactive receiver ignores a late connection callback")
print("RESULT", checks, "checks", failures, "failures")
exit(failures == 0 ? 0 : 1)
