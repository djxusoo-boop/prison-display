#if UNIFIED
import AppKit

// Physical monitors can be switched off and on without unplugging them
// (macOS keeps the cable connected but stops using the monitor). Uses the
// same private call as the system for this; if it is missing, the switch is
// shown disabled. Disabled monitors are remembered so they can be turned on
// again; unplugging and plugging the cable also turns them on.
enum PhysicalDisplays {
    private typealias Enable = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
    private static let enableCall: Enable? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSConfigureDisplayEnabled") else { return nil }
        return unsafeBitCast(symbol, to: Enable.self)
    }()
    static var available: Bool { enableCall != nil }
    static var defaults = UserDefaults.standard
    private static let key = "PrisonDisplay.disabledDisplays"
    // Disabled monitors: display id → name.
    static var disabled: [CGDirectDisplayID: String] {
        let saved = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        return Dictionary(uniqueKeysWithValues: saved.compactMap { k, v in UInt32(k).map { ($0, v) } })
    }
    private static func remember(_ id: CGDirectDisplayID, name: String?) {
        var saved = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        saved[String(id)] = name; defaults.set(saved, forKey: key)
    }
    static func name(_ id: CGDirectDisplayID) -> String {
        if #available(macOS 10.15, *) {
            for screen in NSScreen.screens where (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id { return screen.localizedName }
        }
        return "Monitor externo"
    }
    static func modeText(_ id: CGDirectDisplayID) -> String {
        guard let mode = CGDisplayCopyDisplayMode(id) else { return "" }
        return "\(mode.pixelWidth) × \(mode.pixelHeight) a \(Int(mode.refreshRate.rounded())) Hz"
    }
    static func online() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32); var count: UInt32 = 0
        guard CGGetOnlineDisplayList(32, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
    // Monitors that came back (cable re-plugged) are no longer listed as off.
    static func forgetReturned() {
        let active = Set(online().filter { CGDisplayIsActive($0) != 0 })
        for id in disabled.keys where active.contains(id) { remember(id, name: nil) }
    }
    @discardableResult static func setEnabled(_ id: CGDirectDisplayID, _ on: Bool, name: String) -> String? {
        guard let call = enableCall else { return "Este macOS no permite apagar monitores desde una app." }
        if !on {
            guard CGDisplayIsBuiltin(id) == 0, id != CGMainDisplayID() else { return "La pantalla del Mac y la principal no se apagan: desde ellas controlas todo." }
            let others = online().filter { $0 != id && CGDisplayIsActive($0) != 0 && CGDisplayVendorNumber($0) != 0xA1DE }
            guard !others.isEmpty else { return "Debe quedar al menos otra pantalla encendida." }
        }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return "macOS no aceptó el cambio." }
        guard call(config, id, on) == .success, CGCompleteDisplayConfiguration(config, .forSession) == .success else {
            CGCancelDisplayConfiguration(config); return "macOS no aceptó el cambio."
        }
        remember(id, name: on ? nil : name)
        return nil
    }
}

// "Pantallas": every screen of this Mac in one list, each with its switch.
final class DisplaysPage: NSObject {
    struct Row {
        let title: String
        let detail: String
        let on: Bool
        let enabled: Bool
        let toggle: ((Bool) -> String?)?
    }
    let view: NSView
    var rows: (() -> [Row])?
    private let root = PrisonStack()
    private let list = PrisonStack()
    private let status = NSTextField(wrappingLabelWithString: "")
    private var actions: [ObjectIdentifier: (Bool) -> String?] = [:]
    private var lastKey = ""
    private var timer: Timer?

    override init() {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        view = scroll
        super.init()
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 12, left: 24, bottom: 24, right: 24); root.translatesAutoresizingMaskIntoConstraints = false
        let document = PrisonSidebarDocument(); document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document; document.addSubview(root)
        let fill = root.widthAnchor.constraint(equalTo: document.widthAnchor); fill.priority = .defaultHigh
        NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor), root.centerXAnchor.constraint(equalTo: document.centerXAnchor), root.topAnchor.constraint(equalTo: document.topAnchor), root.bottomAnchor.constraint(equalTo: document.bottomAnchor), root.widthAnchor.constraint(lessThanOrEqualTo: document.widthAnchor), root.widthAnchor.constraint(lessThanOrEqualToConstant: 920), fill])
        let box = NSView(); box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(calibratedRed: 0.105, green: 0.115, blue: 0.14, alpha: 1).cgColor
        box.layer?.borderColor = NSColor(calibratedRed: 0.19, green: 0.20, blue: 0.23, alpha: 1).cgColor
        box.layer?.borderWidth = 1; box.layer?.cornerRadius = 12; box.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(box)
        box.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -48).isActive = true
        list.orientation = .vertical; list.alignment = .leading; list.spacing = 14; list.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(list)
        NSLayoutConstraint.activate([list.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 18), list.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -18), list.topAnchor.constraint(equalTo: box.topAnchor, constant: 18), list.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -18)])
        status.font = .systemFont(ofSize: 12); status.textColor = NSColor(calibratedWhite: 0.7, alpha: 1)
        root.addArrangedSubview(status); status.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -48).isActive = true
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    // Refresh while the page is visible: phases of the virtual screens change.
    func setVisible(_ visible: Bool) {
        timer?.invalidate(); timer = nil
        guard visible else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }
    @objc private func changed() { PhysicalDisplays.forgetReturned(); refresh() }
    func refresh() {
        let current = rows?() ?? []
        let key = current.map { "\($0.title)|\($0.detail)|\($0.on)|\($0.enabled)" }.joined(separator: ";")
        guard key != lastKey else { return }
        lastKey = key
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        actions.removeAll()
        let header = NSTextField(labelWithString: "PANTALLAS DE ESTE MAC"); header.font = .systemFont(ofSize: 11, weight: .semibold); header.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        list.addArrangedSubview(header)
        for row in current {
            let line = NSStackView(); line.orientation = .horizontal; line.alignment = .centerY; line.spacing = 12
            let texts = PrisonStack(); texts.orientation = .vertical; texts.alignment = .leading; texts.spacing = 2
            let title = NSTextField(labelWithString: row.title); title.font = .systemFont(ofSize: 14, weight: .semibold); title.textColor = .white
            let detail = NSTextField(wrappingLabelWithString: row.detail); detail.font = .systemFont(ofSize: 12); detail.textColor = NSColor(calibratedWhite: 0.65, alpha: 1)
            texts.addArrangedSubview(title); texts.addArrangedSubview(detail)
            let toggle = NSButton(checkboxWithTitle: row.on ? "Activa" : "Apagada", target: self, action: #selector(flip(_:)))
            toggle.state = row.on ? .on : .off; toggle.isEnabled = row.enabled && row.toggle != nil
            toggle.setAccessibilityLabel(row.title)
            if let action = row.toggle { actions[ObjectIdentifier(toggle)] = action }
            line.addArrangedSubview(texts); line.addArrangedSubview(toggle)
            toggle.setContentHuggingPriority(.required, for: .horizontal)
            texts.setContentHuggingPriority(.defaultLow, for: .horizontal)
            list.addArrangedSubview(line); line.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
            detail.widthAnchor.constraint(equalTo: texts.widthAnchor).isActive = true
        }
    }
    @objc private func flip(_ sender: NSButton) {
        guard let action = actions[ObjectIdentifier(sender)] else { return }
        let error = action(sender.state == .on)
        status.stringValue = error ?? (sender.state == .on ? "Activada." : "Apagada.")
        lastKey = ""; DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.lastKey = ""; self?.refresh() }
    }
}
#endif
