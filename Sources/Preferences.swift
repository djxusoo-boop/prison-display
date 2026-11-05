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

    // Keep the first three entries in their historical order so existing
    // preferences continue to select the same resolution after an update.
    static let all = [
        DisplayResolutionProfile(title: "1920 × 1080", width: 1920, height: 1080, recommendedFPS: 60),
        DisplayResolutionProfile(title: "1280 × 720", width: 1280, height: 720, recommendedFPS: 60),
        DisplayResolutionProfile(title: "2560 × 1440", width: 2560, height: 1440, recommendedFPS: 30)
    ]

    static let local = [
        DisplayResolutionProfile(title: "2560 × 1440", width: 2560, height: 1440, recommendedFPS: 60),
        DisplayResolutionProfile(title: "3200 × 1800", width: 3200, height: 1800, recommendedFPS: 60),
        DisplayResolutionProfile(title: "3840 × 2160 · 4K", width: 3840, height: 2160, recommendedFPS: 60)
    ]
}

struct LocalVirtualDisplayPreferences: Equatable {
    var resolution: Int
    init(defaults: UserDefaults = .standard) {
        let stored = defaults.object(forKey: "PrisonDisplay.localVirtual.resolution") == nil ? DisplayResolutionProfile.local.count - 1 : defaults.integer(forKey: "PrisonDisplay.localVirtual.resolution")
        resolution = DisplayResolutionProfile.local.indices.contains(stored) ? stored : DisplayResolutionProfile.local.count - 1
    }
    func save(defaults: UserDefaults = .standard) {
        defaults.set(resolution, forKey: "PrisonDisplay.localVirtual.resolution")
    }
}

struct DisplayPreferences: Equatable {
    var mode = 0
    var resolution = 0
    var fps = 0
    var quality = 0
    var cursor = 0
    init(defaults: UserDefaults = .standard, compatibilityDefaults: Bool = false, screenSlot: Int = 0) {
        let prefix = screenSlot == 0 ? "PrisonDisplay.settings." : "PrisonDisplay.settings.2."
        func index(_ key: String, _ count: Int, _ fallback: Int = 0) -> Int {
            guard defaults.object(forKey: prefix + key) != nil else { return fallback }
            let value = defaults.integer(forKey: prefix + key)
            return (0..<count).contains(value) ? value : fallback
        }
        mode = index("mode", 2); resolution = index("resolution", DisplayResolutionProfile.all.count, compatibilityDefaults ? 1 : 0)
        fps = index("fps", 2, compatibilityDefaults ? 1 : 0); quality = index("quality", VideoQualityProfile.all.count); cursor = index("cursor", 2)
    }
    func save(defaults: UserDefaults = .standard, screenSlot: Int = 0) {
        let prefix = screenSlot == 0 ? "PrisonDisplay.settings." : "PrisonDisplay.settings.2."
        for (name, value) in [("mode", mode), ("resolution", resolution), ("fps", fps), ("quality", quality), ("cursor", cursor)] {
            defaults.set(value, forKey: prefix + name)
        }
    }
}

struct ReceiverPreferences: Equatable {
    var mouse: Bool
    var keyboard: Bool
    var crossing: Bool
    var edge: Int
    init(defaults: UserDefaults = .standard) {
        mouse = defaults.object(forKey: "PrisonDisplay.input.mouse") as? Bool ?? true
        keyboard = defaults.bool(forKey: "PrisonDisplay.input.keyboard")
        crossing = defaults.bool(forKey: "PrisonDisplay.input.crossing")
        let stored = defaults.integer(forKey: "desktopEdge")
        edge = (0..<4).contains(stored) ? stored : 0
    }
    func save(defaults: UserDefaults = .standard) {
        defaults.set(mouse, forKey: "PrisonDisplay.input.mouse")
        defaults.set(keyboard, forKey: "PrisonDisplay.input.keyboard")
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
