#if UNIFIED
import AppKit
import CoreGraphics

// The screens of this Mac whose brightness the app can change.
// Built-in panels (and Apple displays) use the system brightness. Other
// monitors, such as an HDMI monitor that ignores brightness over the cable,
// are dimmed by scaling their colour table: it lasts while the app is open.
// Main thread only, except the hardware calls handed to `apply`.
enum LocalBrightness {
    struct Screen { let display: CGDirectDisplayID; let panel: BrightnessPanel }
    static var defaults = UserDefaults.standard
    static let softwareMinimum = 10
    private static var originals: [CGDirectDisplayID: ([CGGammaValue], [CGGammaValue], [CGGammaValue])] = [:]

    static func screens() -> [Screen] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16); var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return [] }
        var result: [Screen] = []
        for display in ids.prefix(Int(count)) where CGDisplayVendorNumber(display) != 0xA1DE {
            let id = panelID(display)
            let hardware = ADBrightness.readDisplay(display)
            let builtin = CGDisplayIsBuiltin(display) != 0
            let name = builtin ? "Pantalla integrada" : externalName(display)
            if hardware >= 0 {
                result.append(Screen(display: display, panel: BrightnessPanel(id: id, name: name, percent: max(5, Int((hardware * 100).rounded())), software: false)))
            } else {
                result.append(Screen(display: display, panel: BrightnessPanel(id: id, name: name, percent: softwareLevel(id), software: true)))
            }
        }
        // Built-in first, then monitors; stable order for the page.
        return Array(result.sorted { ($0.panel.software ? 1 : 0, $0.panel.id) < ($1.panel.software ? 1 : 0, $1.panel.id) }.prefix(BrightnessResult.maxPanels))
    }
    static func panelID(_ display: CGDirectDisplayID) -> String {
        String(format: "%x-%x-%x", CGDisplayVendorNumber(display), CGDisplayModelNumber(display), CGDisplaySerialNumber(display))
    }
    private static func externalName(_ display: CGDirectDisplayID) -> String {
        if #available(macOS 10.15, *) {
            for screen in NSScreen.screens {
                if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                   number.uint32Value == display { return screen.localizedName }
            }
        }
        return "Monitor externo"
    }
    static func softwareLevel(_ id: String) -> Int {
        let saved = defaults.object(forKey: "PrisonDisplay.softBrightness." + id) as? Int ?? 100
        return min(100, max(softwareMinimum, saved))
    }
    // Applies `percent` to the screens accepted by `filter`. Software screens
    // change at once; hardware ones on `queue`. `done` runs on the main thread.
    static func apply(percent: Int, queue: DispatchQueue, filter: (BrightnessPanel) -> Bool, done: @escaping () -> Void) {
        var hardware: [CGDirectDisplayID] = []
        for screen in screens() where filter(screen.panel) {
            if screen.panel.software { setSoftware(screen.display, id: screen.panel.id, percent: percent) }
            else { hardware.append(screen.display) }
        }
        guard !hardware.isEmpty else { done(); return }
        queue.async {
            for display in hardware { _ = ADBrightness.applyDisplay(display, level: Double(min(100, max(5, percent))) / 100) }
            DispatchQueue.main.async(execute: done)
        }
    }
    static func setSoftware(_ display: CGDirectDisplayID, id: String, percent: Int) {
        let level = min(100, max(softwareMinimum, percent))
        defaults.set(level, forKey: "PrisonDisplay.softBrightness." + id)
        _ = dim(display, level: Double(level) / 100)
    }
    // Scales the display's own (calibrated) colour table, so colours stay right.
    @discardableResult static func dim(_ display: CGDirectDisplayID, level: Double) -> Bool {
        if originals[display] == nil {
            guard level < 0.999 else { return true }
            var r = [CGGammaValue](repeating: 0, count: 256), g = r, b = r; var count: UInt32 = 0
            guard CGGetDisplayTransferByTable(display, 256, &r, &g, &b, &count) == .success, count > 1 else { return false }
            let n = Int(count); originals[display] = (Array(r.prefix(n)), Array(g.prefix(n)), Array(b.prefix(n)))
        }
        guard let o = originals[display] else { return false }
        let k = CGGammaValue(min(1, max(0.1, level)))
        return CGSetDisplayTransferByTable(display, UInt32(o.0.count), o.0.map { $0 * k }, o.1.map { $0 * k }, o.2.map { $0 * k }) == .success
    }
    // Screen changes and colour profile reloads reset the table: dim again.
    static func reapplySoftware() {
        originals.removeAll()
        for screen in screens() where screen.panel.software {
            let level = softwareLevel(screen.panel.id)
            if level < 100 { dim(screen.display, level: Double(level) / 100) }
        }
    }
}

// One Mac as shown on the Brightness page.
struct BrightnessNode {
    let node: UUID
    var name: String
    var panels: [BrightnessPanel]
    var seen: Date
    let local: Bool
}

// "Brillo" page: every screen at once, one Mac, or one screen.
final class BrightnessPage: NSObject {
    let view: NSView
    var onSet: ((String?, Int) -> Void)?
    private let root = PrisonStack()
    private let allSlider = NSSlider(value: 60, minValue: 5, maxValue: 100, target: nil, action: nil)
    private let allValue = NSTextField(labelWithString: "—")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var macsStack = PrisonStack()
    private var layoutKey = ""
    private var sliders: [String: (NSSlider, NSTextField)] = [:]
    private var editing: [String: Date] = [:]
    private var targets: [ObjectIdentifier: String] = [:]

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

        let all = card("TODAS LAS PANTALLAS A LA VEZ")
        text("Mueve esta barra para subir o bajar todas las pantallas de los Mac conectados, incluido el monitor HDMI.", in: all)
        let buttons = NSStackView(); buttons.orientation = .horizontal; buttons.spacing = 8
        for (title, action, label) in [("−", #selector(lowerAll), "Bajar brillo de todas"), ("+", #selector(raiseAll), "Subir brillo de todas")] {
            let button = NSButton(title: title, target: self, action: action); button.bezelStyle = .rounded
            button.widthAnchor.constraint(equalToConstant: 44).isActive = true; button.setAccessibilityLabel(label); buttons.addArrangedSubview(button)
        }
        allSlider.target = self; allSlider.action = #selector(changeAll); allSlider.isContinuous = true
        allSlider.setAccessibilityLabel("Brillo de todas las pantallas")
        sliderRow("Todas", allSlider, allValue, extra: buttons, in: all)

        let each = card("CADA PANTALLA POR SEPARADO")
        text("Cada Mac conectado aparece aquí con sus pantallas. Los monitores que no aceptan brillo por el cable se oscurecen desde la app mientras está abierta.", in: each)
        macsStack.orientation = .vertical; macsStack.alignment = .leading; macsStack.spacing = 18
        each.addArrangedSubview(macsStack); macsStack.widthAnchor.constraint(equalTo: each.widthAnchor).isActive = true
        statusLabel.font = .systemFont(ofSize: 12); statusLabel.textColor = NSColor(calibratedWhite: 0.65, alpha: 1)
        root.addArrangedSubview(statusLabel)
    }

    // Rows change only when a Mac or a screen appears or goes; values update in place.
    func update(_ nodes: [BrightnessNode]) {
        let ordered = nodes.sorted { ($0.local ? 0 : 1, $0.name) < ($1.local ? 0 : 1, $1.name) }
        let key = ordered.map { "\($0.node)|\($0.name)|" + $0.panels.map { "\($0.id):\($0.name):\($0.software)" }.joined(separator: ",") }.joined(separator: ";")
        if key != layoutKey { layoutKey = key; rebuild(ordered) }
        let now = Date()
        for node in ordered {
            for panel in node.panels {
                let target = node.node.uuidString + "/" + panel.id
                guard let (slider, value) = sliders[target], (editing[target] ?? .distantPast) < now else { continue }
                if let percent = panel.percent { slider.doubleValue = Double(percent); value.stringValue = "\(percent) %"; slider.isEnabled = true }
                else { value.stringValue = "no disponible"; slider.isEnabled = false }
            }
        }
        if (editing["all"] ?? .distantPast) < now {
            let levels = ordered.flatMap { $0.panels.compactMap { $0.percent } }
            if !levels.isEmpty { let average = levels.reduce(0, +) / levels.count; allSlider.doubleValue = Double(average); allValue.stringValue = "\(average) %" }
        }
        let others = ordered.filter { !$0.local }.count
        statusLabel.stringValue = others == 0 ? "Solo se ve este Mac. Los demás aparecen al conectarlos con Enviar o Recibir pantalla." : "Conectados: \(ordered.map { $0.name }.joined(separator: ", "))."
    }
    func setStatus(_ text: String) { statusLabel.stringValue = text }

    private func rebuild(_ nodes: [BrightnessNode]) {
        macsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        sliders.removeAll(); targets.removeAll()
        for node in nodes {
            let title = NSTextField(labelWithString: node.local ? "\(node.name) · este Mac" : node.name)
            title.font = .systemFont(ofSize: 14, weight: .semibold); title.textColor = .white
            macsStack.addArrangedSubview(title)
            if node.panels.isEmpty { text("No tiene pantallas con brillo ajustable.", in: macsStack); continue }
            if node.panels.count > 1 {
                let slider = makeSlider(target: node.node.uuidString, label: "Todas las pantallas de \(node.name)")
                let value = NSTextField(labelWithString: "")
                sliderRow("Todo este Mac", slider, value, in: macsStack)
            }
            for panel in node.panels {
                let target = node.node.uuidString + "/" + panel.id
                let slider = makeSlider(target: target, label: "\(panel.name) de \(node.name)")
                let value = NSTextField(labelWithString: "—")
                sliderRow(panel.software ? panel.name + " ·  por software" : panel.name, slider, value, in: macsStack)
                sliders[target] = (slider, value)
            }
        }
    }
    private func makeSlider(target: String, label: String) -> NSSlider {
        let slider = NSSlider(value: 60, minValue: 5, maxValue: 100, target: self, action: #selector(changeOne(_:)))
        slider.isContinuous = true; slider.setAccessibilityLabel("Brillo: " + label)
        targets[ObjectIdentifier(slider)] = target
        return slider
    }
    @objc private func changeOne(_ slider: NSSlider) {
        guard let target = targets[ObjectIdentifier(slider)] else { return }
        let percent = Int(slider.doubleValue.rounded())
        editing[target] = Date().addingTimeInterval(1.5)
        if let (_, value) = sliders[target] { value.stringValue = "\(percent) %" }
        // A whole-Mac slider also moves that Mac's screen sliders.
        if !target.contains("/") {
            for (key, pair) in sliders where key.hasPrefix(target + "/") { editing[key] = editing[target]; pair.0.doubleValue = Double(percent); pair.1.stringValue = "\(percent) %" }
        }
        onSet?(target, percent)
    }
    @objc private func changeAll() {
        let percent = Int(allSlider.doubleValue.rounded())
        editing["all"] = Date().addingTimeInterval(1.5); allValue.stringValue = "\(percent) %"
        for (key, pair) in sliders { editing[key] = editing["all"]; pair.0.doubleValue = Double(percent); pair.1.stringValue = "\(percent) %" }
        onSet?(nil, percent)
    }
    @objc private func lowerAll() { allSlider.doubleValue = max(5, allSlider.doubleValue - 10); changeAll() }
    @objc private func raiseAll() { allSlider.doubleValue = min(100, allSlider.doubleValue + 10); changeAll() }

    private func card(_ title: String) -> NSStackView {
        let box = NSView(); box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(calibratedRed: 0.105, green: 0.115, blue: 0.14, alpha: 1).cgColor
        box.layer?.borderColor = NSColor(calibratedRed: 0.19, green: 0.20, blue: 0.23, alpha: 1).cgColor
        box.layer?.borderWidth = 1; box.layer?.cornerRadius = 12; box.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(box)
        box.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -(root.edgeInsets.left + root.edgeInsets.right)).isActive = true
        let inner = PrisonStack(); inner.orientation = .vertical; inner.alignment = .leading; inner.spacing = 10
        inner.translatesAutoresizingMaskIntoConstraints = false; box.addSubview(inner)
        NSLayoutConstraint.activate([inner.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 18), inner.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -18), inner.topAnchor.constraint(equalTo: box.topAnchor, constant: 18), inner.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -18)])
        let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 11, weight: .semibold); label.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        inner.addArrangedSubview(label)
        return inner
    }
    private func text(_ string: String, in stack: NSStackView) {
        let label = NSTextField(wrappingLabelWithString: string); label.font = .systemFont(ofSize: 13); label.textColor = NSColor(calibratedWhite: 0.65, alpha: 1)
        stack.addArrangedSubview(label); label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func sliderRow(_ title: String, _ slider: NSSlider, _ value: NSTextField, extra: NSView? = nil, in stack: NSStackView) {
        let row = NSStackView(); row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 12
        let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 13, weight: .medium); label.textColor = .white
        label.lineBreakMode = .byTruncatingTail; label.widthAnchor.constraint(equalToConstant: 230).isActive = true
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); value.textColor = NSColor(calibratedWhite: 0.75, alpha: 1); value.alignment = .right
        value.widthAnchor.constraint(equalToConstant: 92).isActive = true
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for view in [label, slider, value] + (extra.map { [$0] } ?? []) { row.addArrangedSubview(view) }
        stack.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
}
#endif
