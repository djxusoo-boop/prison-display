#if UNIFIED
import AppKit

enum ScreenRole: String {
    case send, receive
    var title: String { self == .send ? "Enviar pantalla" : "Recibir pantalla" }
    var detail: String { self == .send ? "Usar la pantalla del otro Mac" : "Mostrar aquí la pantalla de otro Mac" }
    static func initial(defaults: UserDefaults, senderIdentity: Bool) -> ScreenRole {
        defaults.string(forKey: "PrisonDisplay.workspace.role").flatMap(ScreenRole.init(rawValue:)) ?? (senderIdentity ? .send : .receive)
    }
    func trustAccount(identifier: String, senderIdentity: Bool) -> String {
        let original: ScreenRole = senderIdentity ? .send : .receive
        return self == original ? identifier : identifier + "." + rawValue
    }
}

final class PrisonSidebarDocument: NSView { override var isFlipped: Bool { true } }

final class RoleButton: NSButton {
    var selected = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let color = selected ? NSColor(calibratedRed: 0.26, green: 0.20, blue: 0.43, alpha: 1) : NSColor.clear
        color.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: selected ? .semibold : .medium), .foregroundColor: selected ? NSColor.white : NSColor(calibratedWhite: 0.7, alpha: 1)]
        (title as NSString).draw(at: NSPoint(x: 16, y: (bounds.height-17)/2), withAttributes: attributes)
    }
}

// Each distribution retains its bundle identity and existing permissions, but
// both contain the same capabilities. Only the selected workflow is active.
final class PrisonWorkspaceController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let sender: SendPanelController
    let secondSender: SendPanelController
    private(set) var selectedScreen = 0
    private var secondEnabled = false
    let secondSendButton = RoleButton(title: "↗  Pantalla 2", target: nil, action: nil)
    let receiver: ReceivePanelController
    private(set) var role: ScreenRole
    private(set) var window: NSWindow!
    let container = NSView()
    let sendButton = RoleButton(title: "↗  Enviar pantalla", target: nil, action: nil)
    let receiveButton = RoleButton(title: "↙  Recibir pantalla", target: nil, action: nil)
    let heading = NSTextField(labelWithString: "")
    let descriptionLabel = NSTextField(wrappingLabelWithString: "")
    let roleHint = NSTextField(wrappingLabelWithString: "")
    let screenSummary = NSTextField(wrappingLabelWithString: "")
    private var summaryTimer: Timer?
    let expertSwitch = NSButton(checkboxWithTitle: "Modo experto", target: nil, action: nil)
    private(set) var expertMode = false

    private let brightnessSlider = NSSlider(value: 50, minValue: 5, maxValue: 100, target: nil, action: nil)
    private let brightnessLabel = NSTextField(labelWithString: "Brillo conjunto · —")
    private let brightnessStatus = NSTextField(wrappingLabelWithString: "Para los Mac conectados")
    private let brightnessQueue = DispatchQueue(label: "PrisonDisplay.brightness", qos: .utility)
    private var brightnessPending: DispatchWorkItem?
    private var brightnessCurrent: UUID?
    private var brightnessSeen: [UUID] = []
    private var brightnessResults: [UUID: BrightnessResult] = [:]
    private let brightnessNode = UUID()
    private var brightnessDeadline: Timer?

    private var sendContent: NSView!
    private var receiveContent: NSView!
    private var secondSendContent: NSView!
    private let workspaceDefaults: UserDefaults
    private var built = false
    init(defaults: UserDefaults = .standard, identifier: String = Bundle.main.bundleIdentifier ?? "local.prisondisplay.preview") {
        workspaceDefaults = defaults
        let identity = identifier == "local.airedisplay.Sender"
        role = ScreenRole.initial(defaults: defaults, senderIdentity: identity)
        sender = SendPanelController(hosted: true, trustAccount: ScreenRole.send.trustAccount(identifier: identifier, senderIdentity: identity))
        secondSender = SendPanelController(hosted: true, trustAccount: ScreenRole.send.trustAccount(identifier: identifier, senderIdentity: identity) + ".screen2", screenSlot: 1)
        secondEnabled = defaults.bool(forKey: "PrisonDisplay.workspace.secondScreen")
        receiver = ReceivePanelController(hosted: true, trustAccount: ScreenRole.receive.trustAccount(identifier: identifier, senderIdentity: identity))
        super.init()
        sender.engine.onBrightnessPacket = { [weak self] kind, data in DispatchQueue.main.async { self?.receiveBrightness(kind, data, source: 0) } }
        secondSender.engine.onBrightnessPacket = { [weak self] kind, data in DispatchQueue.main.async { self?.receiveBrightness(kind, data, source: 1) } }
        receiver.engine.onBrightnessPacket = { [weak self] kind, data in DispatchQueue.main.async { self?.receiveBrightness(kind, data, source: 2) } }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !built else { return }; built = true
        NSApp.setActivationPolicy(.regular)
        sender.applicationDidFinishLaunching(notification); secondSender.applicationDidFinishLaunching(notification); receiver.applicationDidFinishLaunching(notification)
        sendContent = sender.window.contentView; secondSendContent = secondSender.window.contentView; receiveContent = receiver.window.contentView
        sender.window.contentView = nil; secondSender.window.contentView = nil; receiver.window.contentView = nil
        let height = min(900, (NSScreen.main?.visibleFrame.height ?? 950)-70)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: height), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "PRISON DISPLAY · v\(AppVersion.current)"
        window.minSize = NSSize(width: 860, height: 560); window.isReleasedWhenClosed = false; window.delegate = self
        window.backgroundColor = NSColor(calibratedWhite: 0.045, alpha: 1)
        if #available(macOS 10.14, *) { window.appearance = NSAppearance(named: .darkAqua) } else { window.appearance = NSAppearance(named: .vibrantDark) }
        let content = window.contentView!
        let sidebar = NSView(); sidebar.wantsLayer = true; sidebar.layer?.backgroundColor = NSColor(calibratedWhite: 0.075, alpha: 1).cgColor
        expertMode = workspaceDefaults.bool(forKey: "PrisonDisplay.workspace.expert")
        expertSwitch.state = expertMode ? .on : .off; expertSwitch.target = self; expertSwitch.action = #selector(toggleExpertMode)
        let side = PrisonStack(); side.orientation = .vertical; side.alignment = .leading; side.spacing = 14
        let icon = NSImageView(); icon.image = Bundle.main.url(forResource: "PrisonDisplay", withExtension: "icns").flatMap(NSImage.init(contentsOf:)); icon.imageScaling = .scaleProportionallyUpOrDown
        let brand = NSTextField(labelWithString: "PRISON\nDISPLAY"); brand.font = .systemFont(ofSize: 22, weight: .bold); brand.textColor = .white
        let computer = NSTextField(wrappingLabelWithString: Host.current().localizedName ?? "Este Mac"); computer.font = .systemFont(ofSize: 12); computer.textColor = NSColor(calibratedWhite: 0.68, alpha: 1)
        let separator = NSView(); separator.wantsLayer = true; separator.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1).cgColor
        screenSummary.font = .systemFont(ofSize: 11); screenSummary.textColor = NSColor(calibratedWhite: 0.78, alpha: 1)
        roleHint.font = .systemFont(ofSize: 12); roleHint.textColor = NSColor(calibratedWhite: 0.65, alpha: 1)
        brightnessLabel.font = .systemFont(ofSize: 12, weight: .semibold); brightnessLabel.textColor = .white
        brightnessStatus.font = .systemFont(ofSize: 11); brightnessStatus.textColor = NSColor(calibratedWhite: 0.7, alpha: 1)
        brightnessSlider.target = self; brightnessSlider.action = #selector(changeBrightness); brightnessSlider.isContinuous = true
        brightnessSlider.setAccessibilityLabel("Brillo de todos los Mac conectados")
        let brightnessButtons = NSStackView(); brightnessButtons.orientation = .horizontal; brightnessButtons.spacing = 8
        for (title, action) in [("−", #selector(lowerBrightness)), ("+", #selector(raiseBrightness))] {
            let button = NSButton(title: title, target: self, action: action); button.bezelStyle = .rounded; button.widthAnchor.constraint(equalToConstant: 82).isActive = true
            button.setAccessibilityLabel(title == "−" ? "Bajar brillo conjunto" : "Subir brillo conjunto"); brightnessButtons.addArrangedSubview(button)
        }
        for view in [icon, brand, computer, separator, sendButton, secondSendButton, receiveButton, expertSwitch, brightnessLabel, brightnessSlider, brightnessButtons, brightnessStatus, screenSummary, roleHint] { side.addArrangedSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        icon.widthAnchor.constraint(equalToConstant: 86).isActive = true; icon.heightAnchor.constraint(equalToConstant: 86).isActive = true
        for view in [brand, computer, separator, sendButton, secondSendButton, receiveButton, screenSummary, roleHint, expertSwitch, brightnessLabel, brightnessSlider, brightnessButtons, brightnessStatus] { view.widthAnchor.constraint(equalToConstant: 180).isActive = true }
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        for button in [sendButton, secondSendButton, receiveButton] { button.heightAnchor.constraint(equalToConstant: 46).isActive = true; button.target = self; button.isBordered = false }
        sendButton.action = #selector(chooseSend); secondSendButton.action = #selector(chooseSecondSend); receiveButton.action = #selector(chooseReceive)
        let version = NSTextField(labelWithString: "v\(AppVersion.current) · Conexión cifrada"); version.font = .systemFont(ofSize: 11); version.textColor = NSColor(calibratedWhite: 0.65, alpha: 1)
        let header = NSView(); heading.font = .systemFont(ofSize: 25, weight: .bold); heading.textColor = .white
        descriptionLabel.font = .systemFont(ofSize: 13); descriptionLabel.textColor = NSColor(calibratedWhite: 0.65, alpha: 1)
        for view in [sidebar, header, container] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        let sidebarScroll = NSScrollView(); sidebarScroll.hasVerticalScroller = true; sidebarScroll.drawsBackground = false
        let sidebarDocument = PrisonSidebarDocument(); sidebarScroll.documentView = sidebarDocument
        for view in [sidebarScroll, version] { view.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(view) }
        sidebarDocument.translatesAutoresizingMaskIntoConstraints = false; side.translatesAutoresizingMaskIntoConstraints = false; sidebarDocument.addSubview(side)
        NSLayoutConstraint.activate([
            sidebarScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor), sidebarScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor), sidebarScroll.topAnchor.constraint(equalTo: sidebar.topAnchor), sidebarScroll.bottomAnchor.constraint(equalTo: version.topAnchor, constant: -12),
            sidebarDocument.widthAnchor.constraint(equalTo: sidebarScroll.contentView.widthAnchor),
            side.leadingAnchor.constraint(equalTo: sidebarDocument.leadingAnchor, constant: 24), side.topAnchor.constraint(equalTo: sidebarDocument.topAnchor, constant: 24), side.bottomAnchor.constraint(equalTo: sidebarDocument.bottomAnchor, constant: -20),
        ])
        for view in [heading, descriptionLabel] { view.translatesAutoresizingMaskIntoConstraints = false; header.addSubview(view) }
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor), sidebar.topAnchor.constraint(equalTo: content.topAnchor), sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 228),
            side.widthAnchor.constraint(equalToConstant: 180),
            version.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 24), version.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -22),
            header.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), header.trailingAnchor.constraint(equalTo: content.trailingAnchor), header.topAnchor.constraint(equalTo: content.topAnchor), header.heightAnchor.constraint(equalToConstant: 94),
            heading.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 26), heading.topAnchor.constraint(equalTo: header.topAnchor, constant: 20),
            descriptionLabel.leadingAnchor.constraint(equalTo: heading.leadingAnchor), descriptionLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -26), descriptionLabel.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 5),
            container.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), container.trailingAnchor.constraint(equalTo: content.trailingAnchor), container.topAnchor.constraint(equalTo: header.bottomAnchor), container.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        for view in [sendContent!, secondSendContent!, receiveContent!] {
            view.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(view)
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: container.leadingAnchor), view.trailingAnchor.constraint(equalTo: container.trailingAnchor), view.topAnchor.constraint(equalTo: container.topAnchor), view.bottomAnchor.constraint(equalTo: container.bottomAnchor)])
        }
        sender.window = window; secondSender.window = window; receiver.window = window
        let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item); let appMenu = NSMenu(); item.submenu = appMenu
        let about = appMenu.addItem(withTitle: "Acerca de PRISON DISPLAY v\(AppVersion.current)", action: #selector(showAbout), keyEquivalent: ""); about.target = self
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(title: "Editar", action: nil, keyEquivalent: ""); let edit = NSMenu(title: "Editar"); editItem.submenu = edit; menu.addItem(editItem)
        edit.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c"); edit.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v"); edit.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = menu
        brightnessQueue.async { [weak self] in
            let value = ADBrightness.read()
            DispatchQueue.main.async {
                guard let self = self, self.brightnessCurrent == nil else { return }
                if value >= 0 { self.brightnessSlider.doubleValue = max(5, value * 100); self.brightnessLabel.stringValue = "Brillo conjunto · \(Int((value * 100).rounded())) %" }
                else { self.brightnessStatus.stringValue = "Este panel no admite control de brillo" }
            }
        }
        setExpertMode(expertMode)
        refreshRole(); window.center(); window.setFrameAutosaveName("PrisonDisplay.workspace")
        if !CommandLine.arguments.contains("--layout-preview") { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); activate()
            summaryTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshSummary() } }
    }
    @objc private func toggleExpertMode() { setExpertMode(expertSwitch.state == .on) }
    func setExpertMode(_ enabled: Bool) {
        expertMode = enabled; expertSwitch.state = enabled ? .on : .off
        sender.setExpertMode(enabled); secondSender.setExpertMode(enabled); receiver.setExpertMode(enabled)
        if !CommandLine.arguments.contains("--layout-preview") { workspaceDefaults.set(enabled, forKey: "PrisonDisplay.workspace.expert") }
        refreshRole()
    }
    @objc private func lowerBrightness() { brightnessSlider.doubleValue = max(5, brightnessSlider.doubleValue - 10); changeBrightness() }
    @objc private func raiseBrightness() { brightnessSlider.doubleValue = min(100, brightnessSlider.doubleValue + 10); changeBrightness() }
    @objc private func changeBrightness() {
        guard let command = try? BrightnessCommand(percent: Int(brightnessSlider.doubleValue.rounded())) else { return }
        beginBrightness(command, source: nil)
    }
    private func broadcastBrightness(_ kind: Wire.Kind, _ data: Data, except source: Int?) {
        if role == .send {
            if source != 0 { sender.engine.sendBrightness(kind, data) }
            if secondEnabled && source != 1 { secondSender.engine.sendBrightness(kind, data) }
        } else if source != 2 { receiver.engine.sendBrightness(kind, data) }
    }
    private func receiveBrightness(_ kind: Wire.Kind, _ data: Data, source: Int) {
        // Callbacks from a retired role must not affect the new workspace.
        guard (role == .send && source < 2) || (role == .receive && source == 2) else { return }
        if kind == .brightnessCommand, let command = try? BrightnessCommand(data: data) {
            guard !brightnessSeen.contains(command.id) else { return }
            beginBrightness(command, source: source)
        } else if kind == .brightnessResult, let result = try? BrightnessResult(data: data), result.id == brightnessCurrent {
            brightnessResults[result.node] = result; refreshBrightnessStatus()
            // Receiver-originated commands reach the other receiver through the sender.
            if role == .send { broadcastBrightness(kind, data, except: source) }
        }
    }
    private func beginBrightness(_ command: BrightnessCommand, source: Int?) {
        brightnessSeen.append(command.id); if brightnessSeen.count > 64 { brightnessSeen.removeFirst() }
        brightnessCurrent = command.id; brightnessResults.removeAll()
        brightnessSlider.doubleValue = Double(command.percent)
        brightnessLabel.stringValue = "Brillo conjunto · \(command.percent) %"
        brightnessStatus.stringValue = "Aplicando en los Mac conectados…"
        brightnessPending?.cancel(); brightnessDeadline?.invalidate()
        // Collapse slider movement before hardware or network work; no work on the video queue.
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.brightnessCurrent == command.id else { return }
            self.broadcastBrightness(.brightnessCommand, command.data, except: source)
            self.brightnessQueue.async { [weak self] in
                let value = ADBrightness.apply(Double(command.percent) / 100)
                DispatchQueue.main.async {
                    guard let self = self, self.brightnessCurrent == command.id else { return }
                    let result = BrightnessResult(id: command.id, node: self.brightnessNode, name: Host.current().localizedName ?? "Este Mac", percent: value >= 0 ? Int((value * 100).rounded()) : nil)
                    self.brightnessResults[result.node] = result; self.refreshBrightnessStatus()
                    self.broadcastBrightness(.brightnessResult, result.data, except: nil)
                }
            }
        }
        brightnessPending = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        brightnessDeadline = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in self?.refreshBrightnessStatus(timedOut: true) }
    }
    private func refreshBrightnessStatus(timedOut: Bool = false) {
        let rows = brightnessResults.values.sorted { $0.name < $1.name }.map { result -> String in
            if let percent = result.percent { return "\(result.name): \(percent) % ✓" }
            return "\(result.name): no disponible"
        }
        let count = brightnessResults.values.filter { $0.percent != nil }.count
        brightnessStatus.stringValue = "Confirmado en \(count) Mac\n" + rows.joined(separator: "\n") + (timedOut ? "\nSolo se confirman los Mac que responden." : "")
    }
    private func activate() {
        if role == .send {
            sender.activateWorkspace()
            if secondEnabled { secondSender.activateWorkspace() }
        } else { receiver.activateWorkspace() }
    }
    private func refreshSummary() {
        screenSummary.isHidden = role != .send
        screenSummary.stringValue = "Pantalla 1 · " + sender.connectionState.stringValue + "\nPantalla 2 · " + (secondEnabled ? secondSender.connectionState.stringValue : "Elige Pantalla 2 para añadir otro Mac")
    }
    private func refreshRole() {
        refreshSummary()
        sendContent?.isHidden = role != .send || selectedScreen != 0
        secondSendContent?.isHidden = role != .send || selectedScreen != 1
        receiveContent?.isHidden = role != .receive
        secondSendButton.isHidden = role != .send
        sendButton.selected = role == .send && selectedScreen == 0; secondSendButton.selected = role == .send && selectedScreen == 1;
        sendButton.title = expertMode && role == .send ? "↗  Pantalla 1" : "↗  Enviar pantalla"; secondSendButton.title = expertMode ? "↗  Pantalla 2" : "↗  Añadir pantalla"; receiveButton.selected = role == .receive
        heading.stringValue = role.title
        descriptionLabel.stringValue = !expertMode ? (role == .send ? "En el otro Mac, elige Recibir pantalla y selecciona este equipo." : "Elige un Mac disponible y pulsa Conectar. Acepta el mismo código en ambos.") : role == .send ? "Pantalla \(selectedScreen + 1) · Cada receptor tiene su escritorio, conexión y ajustes." : role.detail
        roleHint.stringValue = !expertMode ? "1. Usa Enviar en el Mac principal.\n2. Elige Recibir en los otros Mac.\n3. Comprueba el mismo código." : role == .send ? "Conecta un Mac a Pantalla 1 y el otro a Pantalla 2.\n\nPuedes cambiar entre ambas sin desconectar. Cambiar a Recibir detiene los dos envíos." : "En el otro Mac, elige Enviar pantalla.\n\nAl cambiar de función se detiene la conexión actual."
    }
    func select(_ next: ScreenRole) {
        guard next != role else { return }
        brightnessPending?.cancel(); brightnessDeadline?.invalidate(); brightnessCurrent = nil
        if role == .send { sender.deactivateWorkspace(); secondSender.deactivateWorkspace() } else { receiver.deactivateWorkspace() }
        role = next
        if !CommandLine.arguments.contains("--layout-preview") { UserDefaults.standard.set(role.rawValue, forKey: "PrisonDisplay.workspace.role") }
        refreshRole(); activate()
    }
    @objc func chooseSend() { select(.send); selectedScreen = 0; refreshRole() }
    @objc func chooseSecondSend() {
        select(.send); selectedScreen = 1; secondEnabled = true
        if !CommandLine.arguments.contains("--layout-preview") { UserDefaults.standard.set(true, forKey: "PrisonDisplay.workspace.secondScreen") }
        secondSender.activateWorkspace(); refreshRole()
    }
    @objc func chooseReceive() { select(.receive) }
    @objc func showAbout() { sender.about() }
    func application(_ application: NSApplication, open urls: [URL]) { select(.receive); receiver.application(application, open: urls) }
    func applicationDidBecomeActive(_ notification: Notification) { if role == .receive { receiver.applicationDidBecomeActive(notification) } }
    func applicationWillResignActive(_ notification: Notification) { receiver.applicationWillResignActive(notification) }
    func applicationWillTerminate(_ notification: Notification) { summaryTimer?.invalidate(); summaryTimer = nil; brightnessPending?.cancel(); brightnessDeadline?.invalidate(); sender.deactivateWorkspace(); secondSender.deactivateWorkspace(); receiver.deactivateWorkspace() }
    func windowWillClose(_ notification: Notification) { if (notification.object as? NSWindow) === window { NSApp.terminate(nil) } }
}
#endif
