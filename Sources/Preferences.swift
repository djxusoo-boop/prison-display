import Foundation

// Only remembers authenticated connections; it never approves an unknown Mac.
// Store the user's choice separately for each role and each outgoing screen.
enum ReconnectPreference {
    static func key(_ account: String) -> String { "PrisonDisplay.reconnect." + account }
    static func enabled(account: String, defaults: UserDefaults = .standard) -> Bool {
        let key = key(account)
        return defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }
    static func save(_ enabled: Bool, account: String, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: key(account))
    }
}

// Preferences contain no credentials. Connection keys stay in the Keychain.
struct VideoQualityProfile {
    let title: String
    let ceiling: Int
    // Keep the first three entries stable for preferences saved by older versions.
    static let all = [
        VideoQualityProfile(title: "Automática · hasta 12 Mb/s", ceiling: 12_000_000),
        VideoQualityProfile(title: "Wi-Fi lento · hasta 6 Mb/s", ceiling: 6_000_000),
        VideoQualityProfile(title: "Más calidad · hasta 20 Mb/s", ceiling: 20_000_000),
        VideoQualityProfile(title: "Máxima · hasta 40 Mb/s", ceiling: 40_000_000)
    ]
}

struct DisplayResolutionProfile: Equatable {
    let title: String
    let width: Int
    let height: Int
    let recommendedFPS: Int
    init(title: String, width: Int, height: Int, recommendedFPS: Int) {
        self.title = title; self.width = width; self.height = height; self.recommendedFPS = recommendedFPS
    }
    init(_ width: Int, _ height: Int, note: String? = nil) {
        let base = "\(width) × \(height)"
        self.init(title: note.map { base + " · " + $0 } ?? base, width: width, height: height, recommendedFPS: width * height > 1920 * 1200 ? 30 : 60)
    }
    var aspect: String {
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let d = gcd(width, height); let w = width / d, h = height / d
        return w == 8 && h == 5 ? "16:10" : "\(w):\(h)"
    }

    // Saved preferences store an index into this list: never reorder or remove
    // entries, only append. The menu shows them sorted (see menuOrder).
    static let all = [
        DisplayResolutionProfile(1920, 1080),
        DisplayResolutionProfile(1280, 720),
        DisplayResolutionProfile(2560, 1440),
        DisplayResolutionProfile(3200, 1800),
        DisplayResolutionProfile(3840, 2160, note: "4K"),
        DisplayResolutionProfile(1600, 900),
        DisplayResolutionProfile(2048, 1152),
        DisplayResolutionProfile(2304, 1296),
        DisplayResolutionProfile(2880, 1620),
        DisplayResolutionProfile(3520, 1980),
        DisplayResolutionProfile(1440, 900),
        DisplayResolutionProfile(1680, 1050),
        DisplayResolutionProfile(1920, 1200),
        DisplayResolutionProfile(2304, 1440),
        DisplayResolutionProfile(2560, 1600),
        DisplayResolutionProfile(2880, 1800),
        DisplayResolutionProfile(3200, 2000),
        DisplayResolutionProfile(3456, 2160)
    ]
    // Indices of `all`, grouped by shape and ordered by size for the menu.
    static var menuOrder: [Int] {
        all.indices.sorted { a, b in
            let x = all[a], y = all[b]
            return x.aspect != y.aspect ? x.aspect == "16:9" : x.width < y.width
        }
    }

    // Fallback local sizes when the HDMI monitor reports no usable native mode.
    static let local = [
        DisplayResolutionProfile(title: "2560 × 1440", width: 2560, height: 1440, recommendedFPS: 60),
        DisplayResolutionProfile(title: "3200 × 1800", width: 3200, height: 1800, recommendedFPS: 60),
        DisplayResolutionProfile(title: "3840 × 2160 · 4K", width: 3840, height: 2160, recommendedFPS: 60)
    ]
    // Exact fractions keep common sizes round (1920 × 4/3 = 2560).
    static let localScales: [(numerator: Int, denominator: Int, label: String)] = [
        (5, 4, "1,25"), (4, 3, "1,33"), (3, 2, "1,5"), (5, 3, "1,67"), (7, 4, "1,75"),
        (2, 1, "2"), (9, 4, "2,25"), (5, 2, "2,5"), (8, 3, "2,67"), (3, 1, "3")
    ]
    // More desktop than the monitor shows, keeping its exact shape so it fills
    // the panel without bars. Limited to 5120 × 2880 of virtual desktop.
    static func local(nativeWidth: Int, nativeHeight: Int) -> [DisplayResolutionProfile] {
        guard nativeWidth >= 640, nativeHeight >= 400 else { return local }
        var result: [DisplayResolutionProfile] = []
        for scale in localScales {
            let width = (nativeWidth * scale.numerator / scale.denominator + 4) / 8 * 8
            let height = (width * nativeHeight / nativeWidth + 1) / 2 * 2
            // Measured on an M4 MacBook Air: mirroring stays in hardware (smooth
            // pointer) up to 3840 × 2160 of desktop; larger ones fall back to
            // software scaling and the mouse lags.
            guard width * height <= 3840 * 2160, height >= 400, !result.contains(where: { $0.width == width }) else { continue }
            result.append(DisplayResolutionProfile(title: "\(width) × \(height) · ×\(scale.label) de espacio", width: width, height: height, recommendedFPS: 60))
        }
        return result.isEmpty ? local : result
    }
}

struct LocalVirtualDisplayPreferences: Equatable {
    var resolution: Int
    // Chosen virtual desktop for scaled HDMI menus, e.g. "3840x2160".
    var size: String?
    init(defaults: UserDefaults = .standard) {
        let stored = defaults.object(forKey: "PrisonDisplay.localVirtual.resolution") == nil ? DisplayResolutionProfile.local.count - 1 : defaults.integer(forKey: "PrisonDisplay.localVirtual.resolution")
        resolution = DisplayResolutionProfile.local.indices.contains(stored) ? stored : DisplayResolutionProfile.local.count - 1
        size = defaults.string(forKey: "PrisonDisplay.localVirtual.size")
    }
    func save(defaults: UserDefaults = .standard) {
        defaults.set(resolution, forKey: "PrisonDisplay.localVirtual.resolution")
        if let size = size { defaults.set(size, forKey: "PrisonDisplay.localVirtual.size") }
    }
}

// Size of the video actually sent. The desktop can be larger than the image:
// ScreenCaptureKit scales it on the GPU, so the other Mac shows more space
// without having to decode (or the Wi-Fi carry) every desktop pixel.
struct StreamOutputProfile: Equatable {
    let title: String
    let maxWidth: Int?
    let maxHeight: Int?
    static let all = [
        StreamOutputProfile(title: "Automática · hasta 2560 × 1440", maxWidth: 2560, maxHeight: 1440),
        StreamOutputProfile(title: "Máxima · igual que el escritorio", maxWidth: nil, maxHeight: nil),
        StreamOutputProfile(title: "Hasta 3200 × 1800 · muy nítida", maxWidth: 3200, maxHeight: 1800),
        StreamOutputProfile(title: "Hasta 1920 × 1080 · más fluida", maxWidth: 1920, maxHeight: 1080),
        StreamOutputProfile(title: "Hasta 1600 × 900", maxWidth: 1600, maxHeight: 900),
        StreamOutputProfile(title: "Hasta 1280 × 720 · Wi-Fi lento", maxWidth: 1280, maxHeight: 720)
    ]
    // Fit inside the limit, keep the aspect ratio and use even dimensions (H.264).
    func size(forDesktopWidth width: Int, height: Int) -> (width: Int, height: Int) {
        guard let maxWidth = maxWidth, let maxHeight = maxHeight, width > maxWidth || height > maxHeight else { return (width, height) }
        let scale = min(Double(maxWidth) / Double(width), Double(maxHeight) / Double(height))
        return (max(2, Int(Double(width) * scale) & ~1), max(2, Int(Double(height) * scale) & ~1))
    }
}


struct DisplayPreferences: Equatable {
    var mode = 0
    var resolution = 0
    var fps = 0
    var quality = 0
    var cursor = 0
    var output = 0
    init(defaults: UserDefaults = .standard, compatibilityDefaults: Bool = false, screenSlot: Int = 0) {
        let prefix = screenSlot == 0 ? "PrisonDisplay.settings." : "PrisonDisplay.settings.2."
        func index(_ key: String, _ count: Int, _ fallback: Int = 0) -> Int {
            guard defaults.object(forKey: prefix + key) != nil else { return fallback }
            let value = defaults.integer(forKey: prefix + key)
            return (0..<count).contains(value) ? value : fallback
        }
        mode = index("mode", 2); resolution = index("resolution", DisplayResolutionProfile.all.count, compatibilityDefaults ? 1 : 0)
        fps = index("fps", 2, compatibilityDefaults ? 1 : 0); quality = index("quality", VideoQualityProfile.all.count); cursor = index("cursor", 2)
        output = index("output", StreamOutputProfile.all.count)
    }
    func save(defaults: UserDefaults = .standard, screenSlot: Int = 0) {
        let prefix = screenSlot == 0 ? "PrisonDisplay.settings." : "PrisonDisplay.settings.2."
        for (name, value) in [("mode", mode), ("resolution", resolution), ("fps", fps), ("quality", quality), ("cursor", cursor), ("output", output)] {
            defaults.set(value, forKey: prefix + name)
        }
    }
}

struct ReceiverPreferences: Equatable {
    var mouse: Bool
    var keyboard: Bool
    var crossing: Bool
    var edge: Int
    var continuous: Bool
    init(defaults: UserDefaults = .standard) {
        mouse = defaults.object(forKey: "PrisonDisplay.input.mouse") as? Bool ?? true
        // 0.4.24: the keyboard follows the click by default. Earlier versions
        // started with it off, so typing after clicking the image did nothing.
        keyboard = defaults.object(forKey: "PrisonDisplay.input.keyboard.v2") as? Bool ?? true
        continuous = defaults.object(forKey: "PrisonDisplay.input.continuous") as? Bool ?? true
        crossing = defaults.bool(forKey: "PrisonDisplay.input.crossing")
        let stored = defaults.integer(forKey: "desktopEdge")
        edge = (0..<4).contains(stored) ? stored : 0
    }
    func save(defaults: UserDefaults = .standard) {
        defaults.set(mouse, forKey: "PrisonDisplay.input.mouse")
        defaults.set(keyboard, forKey: "PrisonDisplay.input.keyboard.v2")
        defaults.set(continuous, forKey: "PrisonDisplay.input.continuous")
        defaults.set(crossing, forKey: "PrisonDisplay.input.crossing")
        defaults.set(edge, forKey: "desktopEdge")
    }
}

// Catalina's SDK advertises this API, but its CoreGraphics does not export it.
// Legacy capture enforces TCC itself; modern systems must pass preflight.
import Darwin
enum ScreenCaptureAccess {
    private static let nativeQuery: (() -> Bool)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGPreflightScreenCaptureAccess") else { return nil }
        let function = unsafeBitCast(symbol, to: (@convention(c) () -> Bool).self)
        return { function() }
    }()
    static func permitted() -> Bool {
        permitted(systemMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion, query: nativeQuery)
    }
    static func permitted(systemMajor: Int, query: (() -> Bool)?) -> Bool {
        if systemMajor < 11 { return true }
        return query?() ?? false
    }
}

// App-only input routing; never changes TCC or any system preference.
struct SenderInputPreferences: Equatable {
    var mouse: Bool
    var keyboard: Bool
    init(defaults: UserDefaults = .standard, screenSlot: Int = 0) {
        let prefix = "PrisonDisplay.allowInput.\(screenSlot)."
        mouse = defaults.object(forKey: prefix + "mouse") as? Bool ?? true
        keyboard = defaults.object(forKey: prefix + "keyboard") as? Bool ?? true
    }
    func save(defaults: UserDefaults = .standard, screenSlot: Int = 0) {
        let prefix = "PrisonDisplay.allowInput.\(screenSlot)."
        defaults.set(mouse, forKey: prefix + "mouse")
        defaults.set(keyboard, forKey: prefix + "keyboard")
    }
}
