#if UNIFIED
import AppKit

// Physical monitors are switched "off" in a way that can always be undone:
// the monitor stops being part of the desktop (it mirrors the Mac's screen,
// so windows go back to the Mac) and its picture is blacked out through its
// own colour table. Turning it on removes both. Only public calls; the black
// picture disappears by itself if the app quits. (Disabling a display
// outright is avoided: macOS does not always bring it back.)
enum PhysicalDisplays {
    static var available: Bool { true }
    static var defaults = UserDefaults.standard
    private static let key = "PrisonDisplay.offDisplays"
    // Switched-off monitors: stable key (vendor-model-serial) → name.
    static var off: [String: String] { defaults.dictionary(forKey: key) as? [String: String] ?? [:] }
    static func stableKey(_ id: CGDirectDisplayID) -> String {
        String(format: "%x-%x-%x", CGDisplayVendorNumber(id), CGDisplayModelNumber(id), CGDisplaySerialNumber(id))
    }
    static func isOff(_ id: CGDirectDisplayID) -> Bool { off[stableKey(id)] != nil }
    private static func remember(_ id: CGDirectDisplayID, name: String?) {
        var saved = off; saved[stableKey(id)] = name; defaults.set(saved, forKey: key)
    }
    static func name(_ id: CGDirectDisplayID) -> String {
        if #available(macOS 10.15, *) {
            for screen in NSScreen.screens where (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id { return screen.localizedName }
        }
        return off[stableKey(id)] ?? "Monitor externo"
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
    // External monitors connected now (switched off or not).
    static func externals() -> [CGDirectDisplayID] {
        online().filter { CGDisplayIsBuiltin($0) == 0 && CGDisplayVendorNumber($0) != 0xA1DE }
    }
    private static var blackTimer: Timer?
    // Keep switched-off monitors black (colour profiles can reload the table).
    static func enforce() {
        for id in externals() where isOff(id) {
            if CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay { mirror(id, of: CGMainDisplayID()) }
            CGSetDisplayTransferByFormula(id, 0, 0, 1, 0, 0, 1, 0, 0, 1)
        }
        if off.isEmpty { blackTimer?.invalidate(); blackTimer = nil }
        else if blackTimer == nil {
            let timer = Timer(timeInterval: 2, repeats: true) { _ in enforce() }
            RunLoop.main.add(timer, forMode: .common); blackTimer = timer
        }
    }
    @discardableResult private static func mirror(_ id: CGDirectDisplayID, of main: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        CGConfigureDisplayMirrorOfDisplay(config, id, main)
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }
    // Main thread. Returns an error message, or nil once the change is real.
    @discardableResult static func setEnabled(_ id: CGDirectDisplayID, _ on: Bool, name: String) -> String? {
        guard CGDisplayIsBuiltin(id) == 0, CGDisplayVendorNumber(id) != 0xA1DE else { return "La pantalla del Mac no se apaga: desde ella controlas todo." }
        if !on {
            remember(id, name: name)
            guard mirror(id, of: CGMainDisplayID()) else { remember(id, name: nil); return "macOS no aceptó el cambio." }
            enforce()
            return nil
        }
        remember(id, name: nil)
        guard mirror(id, of: kCGNullDirectDisplay) else { return "macOS no aceptó el cambio." }
        CGDisplayRestoreColorSyncSettings()
        // Restoring the profiles also undoes software brightness: put it back.
        LocalBrightness.reapplySoftware()
        enforce()
        let back = waitUntil(seconds: 5) { CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay && online().contains(id) }
        return back ? nil : "La TV no volvió como pantalla aparte. Desconecta y vuelve a conectar su cable."
    }
    private static func waitUntil(seconds: Double, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > deadline { return false }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return true
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
    @objc private func changed() { PhysicalDisplays.enforce(); refresh() }
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
