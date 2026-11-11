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

enum WorkspaceScreenNames {
    static func key(_ slot: Int) -> String { "PrisonDisplay.workspace.screenName.\(slot + 1)" }
    static func name(slot: Int, defaults: UserDefaults) -> String? {
        guard (0...1).contains(slot), let saved = defaults.string(forKey: key(slot)) else { return nil }
        let cleaned = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(64))
    }
    static func remember(_ name: String, slot: Int, defaults: UserDefaults) {
        guard (0...1).contains(slot) else { return }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        defaults.set(String(cleaned.prefix(64)), forKey: key(slot))
    }
    static func label(slot: Int, defaults: UserDefaults) -> String {
        name(slot: slot, defaults: defaults) ?? "Pantalla \(slot + 1)"
    }
    static func buttonTitle(slot: Int, defaults: UserDefaults) -> String {
        guard let name = name(slot: slot, defaults: defaults) else { return "↗  Pantalla \(slot + 1)" }
        let shortName = name.count > 17 ? String(name.prefix(16)) + "…" : name
        return "↗  " + shortName
    }
}

final class PrisonSidebarDocument: NSView { override var isFlipped: Bool { true } }

final class RoleButton: NSButton {
    var selected = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let color = selected ? prisonAccent : NSColor.clear
        color.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: selected ? .semibold : .medium), .foregroundColor: selected ? NSColor.white : NSColor(calibratedWhite: 0.7, alpha: 1)]
        prisonButtonTitle(title, bounds: bounds.insetBy(dx: 4, dy: 0), font: attributes[.font] as! NSFont, color: attributes[.foregroundColor] as! NSColor, alignment: .left)
    }
}

// Each distribution retains its bundle identity and existing permissions, but
// both contain the same capabilities. Only the selected workflow is active.
final class PrisonWorkspaceController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static func fullscreenTargets(first: StreamPhase, second: StreamPhase, secondEnabled: Bool) -> [Int] {
        var targets: [Int] = []
        if first == .streaming { targets.append(0) }
        if secondEnabled && second == .streaming { targets.append(1) }
        return targets
    }
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
    // Tools have their own pages; nil shows the selected screen role.
    enum Tool: Int { case map, hdmi, pc, brightness, correction }
    private(set) var tool: Tool?
    let mapButton = RoleButton(title: "▦  Mapa de pantallas", target: nil, action: nil)
    let hdmiButton = RoleButton(title: "▭  Monitor HDMI", target: nil, action: nil)
    let pcButton = RoleButton(title: "⊞  PC con Windows", target: nil, action: nil)
    let brightnessButton = RoleButton(title: "☀  Brillo", target: nil, action: nil)
    let brightnessPage = BrightnessPage()
    let correctionButton = RoleButton(title: "⧉  Corregir monitor", target: nil, action: nil)
    #if !LEGACY
    private var correctionPageStorage: AnyObject?
    #endif
    private var brightnessNodes: [UUID: BrightnessNode] = [:]
    private var brightnessQueryTimer: Timer?
    private lazy var brightnessHostName = Host.current().localizedName ?? "Este Mac"
    private var toolPages: [Tool: NSView] = [:]
    let heading = NSTextField(labelWithString: "")
    private let statusPill = PrisonStatusPill(labelWithString: "Sin conexión")
    let descriptionLabel = NSTextField(wrappingLabelWithString: "")
    let roleHint = NSTextField(wrappingLabelWithString: "")
    let screenSummary = NSTextField(wrappingLabelWithString: "")
    let versionButton = NSButton(title: "PRISON DISPLAY · v\(AppVersion.current)", target: nil, action: nil)
    private var summaryTimer: Timer?
    let expertSwitch = NSButton(checkboxWithTitle: "Modo experto", target: nil, action: nil)
    let autoStartSwitch = NSButton(checkboxWithTitle: "Abrir al iniciar sesión", target: nil, action: nil)
    let clipboardSwitch = NSButton(checkboxWithTitle: "Portapapeles compartido", target: nil, action: nil)
    let autoStartStatus = NSTextField(wrappingLabelWithString: "")
    private(set) var expertMode = false

    private let brightnessSlider = NSSlider(value: 50, minValue: 5, maxValue: 100, target: nil, action: nil)
    private let brightnessLabel = NSTextField(labelWithString: "Brillo de todas · —")
    private let brightnessStatus = NSTextField(wrappingLabelWithString: "Cada pantalla por separado: Herramientas → Brillo")
    let fullscreenReceiversButton = PrisonActionButton(title: "Pantalla completa", target: nil, action: nil)
    private let fullscreenReceiversStatus = NSTextField(wrappingLabelWithString: "Envía la orden a las pantallas conectadas")
    private let brightnessQueue = DispatchQueue(label: "PrisonDisplay.brightness", qos: .utility)
    private var brightnessPending: DispatchWorkItem?
    private var brightnessCurrent: UUID?
    private var brightnessSeen: [UUID] = []
    private var brightnessResults: [UUID: BrightnessResult] = [:]
    // Stable across launches so the other Macs keep pointing at the same sliders.
    private lazy var brightnessNode: UUID = {
        if let saved = workspaceDefaults.string(forKey: "PrisonDisplay.brightness.node"), let id = UUID(uuidString: saved) { return id }
        let id = UUID(); if !CommandLine.arguments.contains("--layout-preview") { workspaceDefaults.set(id.uuidString, forKey: "PrisonDisplay.brightness.node") }
        return id
    }()
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
        sender.engine.onPeerConnected = { [weak self] name in DispatchQueue.main.async { self?.rememberConnectedMac(name, slot: 0) } }
        secondSender.engine.onPeerConnected = { [weak self] name in DispatchQueue.main.async { self?.rememberConnectedMac(name, slot: 1) } }
    }
    private func rememberConnectedMac(_ name: String, slot: Int) {
        (slot == 0 ? sender : secondSender).displayPeerName(name)
        WorkspaceScreenNames.remember(name, slot: slot, defaults: workspaceDefaults)
        refreshRole()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !built else { return }; built = true
        NSApp.setActivationPolicy(.regular)
        sender.applicationDidFinishLaunching(notification); secondSender.applicationDidFinishLaunching(notification); receiver.applicationDidFinishLaunching(notification)
        sendContent = sender.window.contentView; secondSendContent = secondSender.window.contentView; receiveContent = receiver.window.contentView
        sender.window.contentView = nil; secondSender.window.contentView = nil; receiver.window.contentView = nil
        let height = min(900, (NSScreen.main?.visibleFrame.height ?? 950)-70)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: height), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "PRISON DISPLAY · v\(AppVersion.current)" + (TestBuild.active ? " · COPIA DE PRUEBA" : "")
        window.minSize = NSSize(width: 860, height: 560); window.isReleasedWhenClosed = false; window.delegate = self
        window.backgroundColor = NSColor(calibratedRed: 0.065, green: 0.075, blue: 0.09, alpha: 1)
        if #available(macOS 10.14, *) { window.appearance = NSAppearance(named: .darkAqua) } else { window.appearance = NSAppearance(named: .vibrantDark) }
        let content = window.contentView!
        content.wantsLayer = true; content.layer?.backgroundColor = window.backgroundColor.cgColor
        let sidebar = NSView(); sidebar.wantsLayer = true; sidebar.layer?.backgroundColor = NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.12, alpha: 1).cgColor
        expertMode = workspaceDefaults.bool(forKey: "PrisonDisplay.workspace.expert")
        expertSwitch.state = expertMode ? .on : .off; expertSwitch.target = self; expertSwitch.action = #selector(toggleExpertMode)
        autoStartSwitch.state = (LoginItemManager.supportsSystemManagedStartup ? AutoLaunchPreference.isEnabled(defaults: workspaceDefaults) : LegacyLoginAgent.isEnabled()) ? .on : .off
        autoStartSwitch.target = self; autoStartSwitch.action = #selector(toggleAutoStart)
        clipboardSwitch.state = ClipboardSync.shared.enabled ? .on : .off
        clipboardSwitch.toolTip = "Copia en un equipo y pega en los demás conectados (texto e imágenes). Las contraseñas de los gestores no se comparten."
        clipboardSwitch.target = self; clipboardSwitch.action = #selector(toggleClipboard)
        let side = PrisonStack(); side.orientation = .vertical; side.alignment = .leading; side.spacing = 12
        let icon = NSImageView(); icon.image = Bundle.main.url(forResource: "PrisonDisplay", withExtension: "icns").flatMap(NSImage.init(contentsOf:)); icon.imageScaling = .scaleProportionallyUpOrDown
        let brand = NSTextField(labelWithString: "PRISON DISPLAY"); brand.font = .systemFont(ofSize: 16, weight: .bold); brand.textColor = .white
        let computer = NSTextField(wrappingLabelWithString: Host.current().localizedName ?? "Este Mac"); computer.font = .systemFont(ofSize: 12); computer.textColor = NSColor(calibratedWhite: 0.68, alpha: 1)
        let separator = NSView(); separator.wantsLayer = true; separator.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1).cgColor
        let screensLabel = NSTextField(labelWithString: "PANTALLAS"), toolsLabel = NSTextField(labelWithString: "HERRAMIENTAS"), optionsLabel = NSTextField(labelWithString: "OPCIONES")
        for label in [screensLabel, toolsLabel, optionsLabel] { label.font = .systemFont(ofSize: 11, weight: .semibold); label.textColor = NSColor(calibratedWhite: 0.5, alpha: 1) }
        screenSummary.font = .systemFont(ofSize: 11); screenSummary.textColor = NSColor(calibratedWhite: 0.78, alpha: 1)
        roleHint.font = .systemFont(ofSize: 12); roleHint.textColor = NSColor(calibratedWhite: 0.65, alpha: 1)
        brightnessLabel.font = .systemFont(ofSize: 12, weight: .semibold); brightnessLabel.textColor = .white
        brightnessStatus.font = .systemFont(ofSize: 11); brightnessStatus.textColor = NSColor(calibratedWhite: 0.7, alpha: 1)
        brightnessSlider.target = self; brightnessSlider.action = #selector(changeBrightness); brightnessSlider.isContinuous = true
        brightnessSlider.setAccessibilityLabel("Brillo de todos los Mac conectados")
        fullscreenReceiversButton.target = self; fullscreenReceiversButton.action = #selector(fullscreenReceivers)
        fullscreenReceiversButton.heightAnchor.constraint(equalToConstant: 38).isActive = true
        fullscreenReceiversButton.setAccessibilityLabel("Poner a pantalla completa los visores remotos conectados")
        fullscreenReceiversButton.toolTip = "Abre a pantalla completa cada visor que esté conectado, sin mover el ratón a esos Mac."
        fullscreenReceiversStatus.font = .systemFont(ofSize: 11); fullscreenReceiversStatus.textColor = NSColor(calibratedWhite: 0.7, alpha: 1)
        let brightnessButtons = NSStackView(); brightnessButtons.orientation = .horizontal; brightnessButtons.spacing = 8
        for (title, action) in [("−", #selector(lowerBrightness)), ("+", #selector(raiseBrightness))] {
            let button = NSButton(title: title, target: self, action: action); button.bezelStyle = .rounded; button.widthAnchor.constraint(equalToConstant: 82).isActive = true
            button.setAccessibilityLabel(title == "−" ? "Bajar brillo conjunto" : "Subir brillo conjunto"); brightnessButtons.addArrangedSubview(button)
        }
        autoStartStatus.font = .systemFont(ofSize: 11); autoStartStatus.textColor = NSColor(calibratedWhite: 0.7, alpha: 1); autoStartStatus.isHidden = true
        for view in [icon, brand, computer, separator, screensLabel, sendButton, secondSendButton, receiveButton, screenSummary, toolsLabel, mapButton, brightnessButton, hdmiButton, correctionButton, pcButton, optionsLabel, clipboardSwitch, autoStartSwitch, expertSwitch, autoStartStatus] { side.addArrangedSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        icon.widthAnchor.constraint(equalToConstant: 56).isActive = true; icon.heightAnchor.constraint(equalToConstant: 56).isActive = true
        for view in [brand, computer, separator, screensLabel, sendButton, secondSendButton, receiveButton, screenSummary, toolsLabel, mapButton, brightnessButton, hdmiButton, correctionButton, pcButton, optionsLabel, expertSwitch, clipboardSwitch, autoStartSwitch, autoStartStatus] { view.widthAnchor.constraint(equalToConstant: 200).isActive = true }
        side.setCustomSpacing(22, after: screenSummary); side.setCustomSpacing(22, after: pcButton)
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        for button in [sendButton, secondSendButton, receiveButton] { button.heightAnchor.constraint(equalToConstant: 46).isActive = true; button.target = self; button.isBordered = false }
        for button in [mapButton, brightnessButton, hdmiButton, correctionButton, pcButton] { button.heightAnchor.constraint(equalToConstant: 40).isActive = true; button.target = self; button.isBordered = false; button.action = #selector(chooseTool(_:)) }
        mapButton.tag = Tool.map.rawValue; brightnessButton.tag = Tool.brightness.rawValue; correctionButton.tag = Tool.correction.rawValue; hdmiButton.tag = Tool.hdmi.rawValue; pcButton.tag = Tool.pc.rawValue
        sendButton.action = #selector(chooseSend); secondSendButton.action = #selector(chooseSecondSend); receiveButton.action = #selector(chooseReceive)
        let version = versionButton
        version.font = .systemFont(ofSize: 11); version.alignment = .left; version.isBordered = false; version.bezelStyle = .inline
        version.controlSize = .small; version.target = self; version.action = #selector(footerAction)
        version.toolTip = "Pulsa para abrir la pantalla recibida a pantalla completa"
        if #available(macOS 10.14, *) { version.contentTintColor = NSColor(calibratedWhite: 0.65, alpha: 1) }
        // Shared display controls are separate from navigation and stay reachable.
        let utility = NSView(); utility.wantsLayer = true; utility.layer?.backgroundColor = NSColor(calibratedRed: 0.105, green: 0.115, blue: 0.14, alpha: 1).cgColor
        let utilityRow = NSStackView(); utilityRow.orientation = .horizontal; utilityRow.spacing = 24; utilityRow.distribution = .fillEqually; utilityRow.alignment = .top
        let light = PrisonStack(); light.orientation = .vertical; light.alignment = .leading; light.spacing = 6
        let presentation = PrisonStack(); presentation.orientation = .vertical; presentation.alignment = .leading; presentation.spacing = 6
        for view in [brightnessLabel, brightnessSlider, brightnessButtons] { light.addArrangedSubview(view) }
        for view in [fullscreenReceiversButton, fullscreenReceiversStatus] { presentation.addArrangedSubview(view) }
        utilityRow.addArrangedSubview(light); utilityRow.addArrangedSubview(presentation)
        utilityRow.translatesAutoresizingMaskIntoConstraints = false; utility.addSubview(utilityRow)
        for view in [brightnessSlider, fullscreenReceiversButton, fullscreenReceiversStatus] { view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([utilityRow.leadingAnchor.constraint(equalTo: utility.leadingAnchor, constant: 24), utilityRow.trailingAnchor.constraint(equalTo: utility.trailingAnchor, constant: -24), utilityRow.topAnchor.constraint(equalTo: utility.topAnchor, constant: 14), brightnessSlider.widthAnchor.constraint(equalTo: light.widthAnchor), fullscreenReceiversButton.widthAnchor.constraint(equalTo: presentation.widthAnchor), fullscreenReceiversStatus.widthAnchor.constraint(equalTo: presentation.widthAnchor)])
        brightnessStatus.maximumNumberOfLines = 2; fullscreenReceiversStatus.maximumNumberOfLines = 2
        brightnessStatus.lineBreakMode = .byTruncatingTail; fullscreenReceiversStatus.lineBreakMode = .byTruncatingTail
        let header = NSView(); heading.font = .systemFont(ofSize: 25, weight: .bold); heading.textColor = .white
        descriptionLabel.font = .systemFont(ofSize: 13); descriptionLabel.textColor = NSColor(calibratedWhite: 0.65, alpha: 1)
        for view in [sidebar, header, container, utility] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        let sidebarScroll = NSScrollView(); sidebarScroll.hasVerticalScroller = true; sidebarScroll.drawsBackground = false
        let sidebarDocument = PrisonSidebarDocument(); sidebarScroll.documentView = sidebarDocument
        for view in [sidebarScroll, version] { view.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(view) }
        sidebarDocument.translatesAutoresizingMaskIntoConstraints = false; side.translatesAutoresizingMaskIntoConstraints = false; sidebarDocument.addSubview(side)
        NSLayoutConstraint.activate([
            sidebarScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor), sidebarScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor), sidebarScroll.topAnchor.constraint(equalTo: sidebar.topAnchor), sidebarScroll.bottomAnchor.constraint(equalTo: version.topAnchor, constant: -12),
            sidebarDocument.widthAnchor.constraint(equalTo: sidebarScroll.contentView.widthAnchor),
            side.leadingAnchor.constraint(equalTo: sidebarDocument.leadingAnchor, constant: 24), side.topAnchor.constraint(equalTo: sidebarDocument.topAnchor, constant: 24), side.bottomAnchor.constraint(equalTo: sidebarDocument.bottomAnchor, constant: -20),
        ])
        statusPill.font = .systemFont(ofSize: 11, weight: .medium); statusPill.alignment = .center
        statusPill.wantsLayer = true; statusPill.layer?.cornerRadius = 17; statusPill.layer?.masksToBounds = true
        statusPill.layer?.backgroundColor = NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 1).cgColor
        for view in [heading, descriptionLabel, statusPill] { view.translatesAutoresizingMaskIntoConstraints = false; header.addSubview(view) }
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor), sidebar.topAnchor.constraint(equalTo: content.topAnchor), sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 248),
            side.widthAnchor.constraint(equalToConstant: 200),
            version.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 24), version.trailingAnchor.constraint(lessThanOrEqualTo: sidebar.trailingAnchor, constant: -16), version.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -22),
            header.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), header.trailingAnchor.constraint(equalTo: content.trailingAnchor), header.topAnchor.constraint(equalTo: content.topAnchor), header.heightAnchor.constraint(equalToConstant: 94),
            statusPill.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -24), statusPill.topAnchor.constraint(equalTo: header.topAnchor, constant: 20), statusPill.widthAnchor.constraint(equalToConstant: 184), statusPill.heightAnchor.constraint(equalToConstant: 34),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: statusPill.leadingAnchor, constant: -12),
            heading.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 26), heading.topAnchor.constraint(equalTo: header.topAnchor, constant: 20),
            descriptionLabel.leadingAnchor.constraint(equalTo: heading.leadingAnchor), descriptionLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -26), descriptionLabel.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 5),
            utility.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), utility.trailingAnchor.constraint(equalTo: content.trailingAnchor), utility.bottomAnchor.constraint(equalTo: content.bottomAnchor), utility.heightAnchor.constraint(equalToConstant: 112),
            container.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), container.trailingAnchor.constraint(equalTo: content.trailingAnchor), container.topAnchor.constraint(equalTo: header.bottomAnchor), container.bottomAnchor.constraint(equalTo: utility.topAnchor)
        ])
        toolPages = [.map: sender.mapPage, .hdmi: sender.hdmiPage, .pc: sender.pcPage].compactMapValues { $0 }
        toolPages[.brightness] = brightnessPage.view
        correctionButton.isHidden = true
        #if !LEGACY
        if #available(macOS 12.3, *) {
            let page = CorrectionPage(); correctionPageStorage = page
            toolPages[.correction] = page.view; correctionButton.isHidden = false
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                if self?.tool == .correction, !page.engine.active { page.reload() }
            }
        }
        #endif
        brightnessPage.onSet = { [weak self] target, percent in self?.setBrightness(target: target, percent: percent) }
        pcButton.isHidden = toolPages[.pc] == nil
        for view in [sendContent!, secondSendContent!, receiveContent!] + Array(toolPages.values) {
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
        LocalBrightness.reapplySoftware()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            LocalBrightness.reapplySoftware(); if self?.tool == .brightness { self?.refreshBrightnessPage() }
        }
        brightnessQueue.async { [weak self] in
            let value = ADBrightness.read()
            DispatchQueue.main.async {
                guard let self = self, self.brightnessCurrent == nil else { return }
                if value >= 0 { self.brightnessSlider.doubleValue = max(5, value * 100); self.brightnessLabel.stringValue = "Brillo de todas · \(Int((value * 100).rounded())) %" }
                else { self.brightnessStatus.stringValue = "Cada pantalla por separado: Herramientas → Brillo" }
            }
        }
        setExpertMode(expertMode)
        refreshRole(); window.center(); window.setFrameAutosaveName("PrisonDisplay.workspace")
        if !CommandLine.arguments.contains("--layout-preview") { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); activate(); applyAutoStartPreference()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in OldCopies.offerCleanup(window: self?.window) }
            summaryTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshSummary() } }
    }
    @objc private func toggleClipboard() { ClipboardSync.shared.enabled = clipboardSwitch.state == .on }
    @objc private func toggleExpertMode() { setExpertMode(expertSwitch.state == .on) }
    private func applyAutoStartPreference() {
        if TestBuild.active {
            autoStartSwitch.isEnabled = false
            autoStartStatus.stringValue = "Copia de prueba: no se abre al iniciar sesión ni cambia la app instalada."; autoStartStatus.isHidden = false
            return
        }
        guard LoginItemManager.supportsSystemManagedStartup else {
            // Keep the agent pointing at this copy (it may have been moved or updated).
            if LegacyLoginAgent.isEnabled() { try? LegacyLoginAgent.setEnabled(true) }
            autoStartSwitch.state = LegacyLoginAgent.isEnabled() ? .on : .off
            return
        }
        let enabled = AutoLaunchPreference.isEnabled(defaults: workspaceDefaults)
        AutoLaunchPreference.save(enabled, defaults: workspaceDefaults)
        do { showAutoStartState(try LoginItemManager.setEnabled(enabled)) }
        catch { autoStartSwitch.state = LoginItemManager.state() == .enabled ? .on : .off; autoStartStatus.stringValue = "No se pudo configurar el inicio automático: \(error.localizedDescription)"; autoStartStatus.isHidden = false }
    }
    @objc private func toggleAutoStart() {
        let enabled = autoStartSwitch.state == .on
        guard LoginItemManager.supportsSystemManagedStartup else {
            do { try LegacyLoginAgent.setEnabled(enabled); autoStartStatus.isHidden = true }
            catch { autoStartStatus.stringValue = "No se pudo cambiar el inicio automático: \(error.localizedDescription)"; autoStartStatus.isHidden = false }
            autoStartSwitch.state = LegacyLoginAgent.isEnabled() ? .on : .off
            return
        }
        do {
            let state = try LoginItemManager.setEnabled(enabled)
            AutoLaunchPreference.save(enabled, defaults: workspaceDefaults)
            showAutoStartState(state)
        } catch {
            autoStartSwitch.state = LoginItemManager.state() == .enabled ? .on : .off
            autoStartStatus.stringValue = "No se pudo cambiar el inicio automático: \(error.localizedDescription)"
            autoStartStatus.isHidden = false
        }
    }
    private func showAutoStartState(_ state: LoginItemState) {
        autoStartSwitch.state = state == .disabled ? .off : .on
        switch state {
        case .enabled:
            autoStartStatus.stringValue = "Se abrirá con macOS y recuperará conexiones guardadas."
            autoStartStatus.isHidden = true
        case .approvalRequired:
            autoStartStatus.stringValue = "macOS espera aprobación en General → Ítems de inicio."
            autoStartStatus.isHidden = false
        case .disabled:
            autoStartStatus.stringValue = "Inicio automático desactivado."
            autoStartStatus.isHidden = true
        }
    }
    func setExpertMode(_ enabled: Bool) {
        expertMode = enabled; expertSwitch.state = enabled ? .on : .off
        sender.setExpertMode(enabled); secondSender.setExpertMode(enabled); receiver.setExpertMode(enabled)
        if !CommandLine.arguments.contains("--layout-preview") { workspaceDefaults.set(enabled, forKey: "PrisonDisplay.workspace.expert") }
        refreshRole()
    }
    @objc private func lowerBrightness() { brightnessSlider.doubleValue = max(5, brightnessSlider.doubleValue - 10); changeBrightness() }
    @objc private func raiseBrightness() { brightnessSlider.doubleValue = min(100, brightnessSlider.doubleValue + 10); changeBrightness() }
    @objc private func changeBrightness() { setBrightness(target: nil, percent: Int(brightnessSlider.doubleValue.rounded())) }
    // nil = every screen of every connected Mac; "node" or "node/screen" = one.
    func setBrightness(target: String?, percent: Int) {
        guard let command = try? BrightnessCommand(percent: percent, target: target) else { return }
        if target == nil { brightnessSlider.doubleValue = Double(percent); brightnessLabel.stringValue = "Brillo de todas · \(percent) %" }
        brightnessPending?.cancel()
        // Collapse slider movement before hardware or network work; no work on the video queue.
        let work = DispatchWorkItem { [weak self] in self?.beginBrightness(command, source: nil) }
        brightnessPending = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
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
        } else if kind == .brightnessResult, let result = try? BrightnessResult(data: data), result.node != brightnessNode {
            recordBrightness(result)
            if result.id == brightnessCurrent { brightnessResults[result.node] = result; refreshBrightnessStatus() }
            // Receiver-originated commands reach the other receiver through the sender.
            if role == .send { broadcastBrightness(kind, data, except: source) }
        }
    }
    private func beginBrightness(_ command: BrightnessCommand, source: Int?) {
        brightnessSeen.append(command.id); if brightnessSeen.count > 64 { brightnessSeen.removeFirst() }
        if !command.isQuery {
            brightnessCurrent = command.id; brightnessResults.removeAll()
            if command.target == nil {
                brightnessSlider.doubleValue = Double(command.percent)
                brightnessLabel.stringValue = "Brillo de todas · \(command.percent) %"
            }
            brightnessStatus.stringValue = "Aplicando…"
            brightnessDeadline?.invalidate()
            brightnessDeadline = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in self?.refreshBrightnessStatus(timedOut: true) }
        }
        broadcastBrightness(.brightnessCommand, command.data, except: source)
        let node = brightnessNode
        LocalBrightness.apply(percent: command.percent, queue: brightnessQueue, filter: { command.applies(node: node, panel: $0.id) }) { [weak self] in
            guard let self = self else { return }
            let panels = LocalBrightness.screens().map { $0.panel }
            let result = BrightnessResult(id: command.id, node: node, name: self.brightnessHostName, percent: panels.first?.percent, panels: panels)
            self.recordBrightness(result)
            if result.id == self.brightnessCurrent { self.brightnessResults[result.node] = result; self.refreshBrightnessStatus() }
            self.broadcastBrightness(.brightnessResult, result.data, except: nil)
        }
    }
    private func recordBrightness(_ result: BrightnessResult) {
        let local = result.node == brightnessNode
        let panels = result.panels ?? (result.percent.map { [BrightnessPanel(id: "panel", name: "Pantalla", percent: $0, software: false)] } ?? [])
        brightnessNodes[result.node] = BrightnessNode(node: result.node, name: result.name, panels: panels, seen: Date(), local: local)
        refreshBrightnessPage()
    }
    private func refreshBrightnessPage() {
        let limit = Date().addingTimeInterval(-14)
        brightnessNodes = brightnessNodes.filter { $0.value.local || $0.value.seen > limit }
        if brightnessNodes[brightnessNode] == nil {
            brightnessNodes[brightnessNode] = BrightnessNode(node: brightnessNode, name: brightnessHostName, panels: LocalBrightness.screens().map { $0.panel }, seen: Date(), local: true)
        }
        brightnessPage.update(Array(brightnessNodes.values))
    }
    // While the Brightness page is open, ask the connected Macs for their screens.
    private func refreshBrightnessQueries() {
        let visible = tool == .brightness
        if visible, brightnessQueryTimer == nil {
            let ask = { [weak self] in
                guard let self = self else { return }
                self.brightnessNodes[self.brightnessNode] = nil
                self.beginBrightness(BrightnessCommand.query(), source: nil)
            }
            ask(); refreshBrightnessPage()
            brightnessQueryTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in ask() }
        } else if !visible {
            brightnessQueryTimer?.invalidate(); brightnessQueryTimer = nil
        }
    }
    private func refreshBrightnessStatus(timedOut: Bool = false) {
        let rows = brightnessResults.values.sorted { $0.name < $1.name }.map { result -> String in
            let levels = (result.panels ?? []).compactMap { $0.percent }
            if let percent = levels.first ?? result.percent { return "\(result.name): \(percent) % ✓" }
            return "\(result.name): no disponible"
        }
        let count = brightnessResults.count
        brightnessStatus.stringValue = "Confirmado en \(count) Mac\n" + rows.joined(separator: "\n") + (timedOut ? "\nSolo se confirman los Mac que responden." : "")
    }
    private func activate() {
        if role == .send {
            sender.activateWorkspace()
            if secondEnabled { secondSender.activateWorkspace() }
        } else { receiver.activateWorkspace() }
    }
    private func refreshSummary() {
        sender.connectionOverview.remoteName = WorkspaceScreenNames.label(slot: 0, defaults: workspaceDefaults)
        secondSender.connectionOverview.remoteName = WorkspaceScreenNames.label(slot: 1, defaults: workspaceDefaults)
        let phase = role == .receive ? receiver.engine.phase : (selectedScreen == 0 ? sender.engine.phase : secondSender.engine.phase)
        statusPill.stringValue = "●  " + phase.title; statusPill.textColor = phase.color
        statusPill.toolTip = phase.title
        screenSummary.isHidden = role != .send
        screenSummary.maximumNumberOfLines = 4
        screenSummary.stringValue = WorkspaceScreenNames.label(slot: 0, defaults: workspaceDefaults) + " · " + sender.connectionState.stringValue + "\n" + WorkspaceScreenNames.label(slot: 1, defaults: workspaceDefaults) + " · " + (secondEnabled ? secondSender.connectionState.stringValue : "Elige la segunda pantalla para añadir otro Mac")
        let targets = Self.fullscreenTargets(first: sender.engine.phase, second: secondSender.engine.phase, secondEnabled: secondEnabled)
        fullscreenReceiversButton.title = role == .send ? "Pantalla completa" : "Abrir visor"
        fullscreenReceiversButton.isEnabled = role == .send ? !targets.isEmpty : receiver.engine.phase == .streaming
        fullscreenReceiversButton.isHidden = false
        fullscreenReceiversStatus.isHidden = false
        fullscreenReceiversStatus.stringValue = role == .receive
            ? "Muestra la pantalla recibida. Esc para salir."
            : (!targets.isEmpty ? "Se aplicará a los Mac conectados." : "Disponible al conectar una pantalla.")
    }
    private func refreshRole() {
        refreshSummary()
        versionButton.toolTip = role == .receive
            ? "Pulsa para abrir la pantalla recibida a pantalla completa"
            : "Pulsa para poner PRISON DISPLAY a pantalla completa"
        sendContent?.isHidden = tool != nil || role != .send || selectedScreen != 0
        secondSendContent?.isHidden = tool != nil || role != .send || selectedScreen != 1
        receiveContent?.isHidden = tool != nil || role != .receive
        for (kind, page) in toolPages { page.isHidden = tool != kind }
        mapButton.selected = tool == .map; brightnessButton.selected = tool == .brightness; correctionButton.selected = tool == .correction; hdmiButton.selected = tool == .hdmi; pcButton.selected = tool == .pc
        secondSendButton.isHidden = role != .send
        sendButton.selected = tool == nil && role == .send && selectedScreen == 0; secondSendButton.selected = tool == nil && role == .send && selectedScreen == 1;
        sendButton.title = expertMode && role == .send ? WorkspaceScreenNames.buttonTitle(slot: 0, defaults: workspaceDefaults) : "↗  Enviar pantalla"; secondSendButton.title = expertMode ? (WorkspaceScreenNames.name(slot: 1, defaults: workspaceDefaults) == nil ? "↗  Añadir pantalla" : WorkspaceScreenNames.buttonTitle(slot: 1, defaults: workspaceDefaults)) : "↗  Añadir pantalla"; receiveButton.selected = tool == nil && role == .receive
        heading.stringValue = role.title
        if let tool = tool {
            heading.stringValue = ["Mapa de pantallas", "Monitor HDMI", "PC con Windows", "Brillo", "Corregir monitor"][tool.rawValue]
            descriptionLabel.stringValue = ["Coloca tus pantallas y el PC arrastrándolos.", "Más espacio de escritorio en un monitor conectado por cable.", "Usa el ratón, el teclado y el portapapeles de este Mac en tu PC.", "Sube o baja el brillo de todas las pantallas a la vez o de cada una por separado.", "Muestra el escritorio completo en un monitor o TV con otra proporción, sin deformarlo ni cortarlo."][tool.rawValue]
            return
        }
        descriptionLabel.stringValue = !expertMode ? (role == .send ? "En el otro Mac, elige Recibir pantalla y selecciona este equipo." : "Pulsa Conectar junto al Mac disponible o enlazado. La primera vez, confirma el código.") : role == .send ? "\(WorkspaceScreenNames.label(slot: selectedScreen, defaults: workspaceDefaults)) · Cada receptor tiene su escritorio, conexión y ajustes." : role.detail
        roleHint.stringValue = !expertMode ? "1. Usa Enviar en el Mac principal.\n2. Elige Recibir en los otros Mac.\n3. Comprueba el mismo código." : role == .send ? "Conecta un Mac a \(WorkspaceScreenNames.label(slot: 0, defaults: workspaceDefaults)) y otro a \(WorkspaceScreenNames.label(slot: 1, defaults: workspaceDefaults)).\n\nPuedes cambiar entre ambas sin desconectar. Cambiar a Recibir detiene los dos envíos." : "En el otro Mac, elige Enviar pantalla.\n\nAl cambiar de función se detiene la conexión actual."
    }
    func select(_ next: ScreenRole) {
        guard next != role else { return }
        brightnessPending?.cancel(); brightnessDeadline?.invalidate(); brightnessCurrent = nil
        if role == .send { sender.deactivateWorkspace(); secondSender.deactivateWorkspace() } else { receiver.deactivateWorkspace() }
        role = next
        if !CommandLine.arguments.contains("--layout-preview") { UserDefaults.standard.set(role.rawValue, forKey: "PrisonDisplay.workspace.role") }
        refreshRole(); activate()
    }
    @objc func chooseTool(_ sender: NSButton) {
        tool = Tool(rawValue: sender.tag); refreshRole(); refreshBrightnessQueries()
        #if !LEGACY
        if tool == .correction, #available(macOS 12.3, *), let page = correctionPageStorage as? CorrectionPage, !page.engine.active { page.reload() }
        #endif
    }
    @objc func chooseSend() { tool = nil; refreshBrightnessQueries(); select(.send); selectedScreen = 0; refreshRole() }
    @objc func chooseSecondSend() {
        tool = nil; refreshBrightnessQueries(); select(.send); selectedScreen = 1; secondEnabled = true
        if !CommandLine.arguments.contains("--layout-preview") { UserDefaults.standard.set(true, forKey: "PrisonDisplay.workspace.secondScreen") }
        secondSender.activateWorkspace(); refreshRole()
    }
    @objc func chooseReceive() { tool = nil; refreshBrightnessQueries(); select(.receive); refreshRole() }
    @objc private func fullscreenReceivers() {
        if role == .receive { receiver.fullscreen(); return }
        guard role == .send, secondEnabled else { return }
        let targets = Self.fullscreenTargets(first: sender.engine.phase, second: secondSender.engine.phase, secondEnabled: secondEnabled)
        guard !targets.isEmpty else {
            fullscreenReceiversStatus.stringValue = "No hay pantallas conectadas ahora."
            return
        }
        if targets.contains(0) { sender.engine.requestFullscreen() }
        if targets.contains(1) { secondSender.engine.requestFullscreen() }
        let names = targets.map { "Pantalla \($0 + 1)" }
        fullscreenReceiversStatus.stringValue = "Orden enviada a " + names.joined(separator: " y ") + "."
    }
    @objc func footerAction() {
        if role == .receive { receiver.fullscreen() }
        else { window.toggleFullScreen(nil) }
    }
    @objc func showAbout() { sender.about() }
    func application(_ application: NSApplication, open urls: [URL]) { select(.receive); receiver.application(application, open: urls) }
    func applicationDidBecomeActive(_ notification: Notification) {
        #if !LEGACY
        WindowsLink.shared.bridge.applicationDidBecomeActive()
        #endif
        if role == .receive { receiver.applicationDidBecomeActive(notification) }
    }
    func applicationWillResignActive(_ notification: Notification) {
        #if !LEGACY
        WindowsLink.shared.bridge.applicationDidResignActive()
        #endif
        receiver.applicationWillResignActive(notification)
    }
    func applicationWillTerminate(_ notification: Notification) { summaryTimer?.invalidate(); summaryTimer = nil; brightnessQueryTimer?.invalidate();
        #if !LEGACY
        if #available(macOS 12.3, *) { (correctionPageStorage as? CorrectionPage)?.engine.stop(reason: nil) }
        #endif
        brightnessPending?.cancel(); brightnessDeadline?.invalidate(); sender.deactivateWorkspace(); secondSender.deactivateWorkspace(); receiver.deactivateWorkspace()
        #if !LEGACY
        WindowsLink.shared.bridge.stop()
        #endif
    }
    func windowWillClose(_ notification: Notification) { if (notification.object as? NSWindow) === window { NSApp.terminate(nil) } }
}
#endif
