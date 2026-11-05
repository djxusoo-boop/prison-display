import Foundation

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

struct DisplayPreferences: Equatable {
    var mode = 0
    var resolution = 0
    var fps = 0
    var quality = 0
    var cursor = 0
    init(defaults: UserDefaults = .standard, compatibilityDefaults: Bool = false) {
        func index(_ key: String, _ count: Int, _ fallback: Int = 0) -> Int {
            guard defaults.object(forKey: "PrisonDisplay.settings." + key) != nil else { return fallback }
            let value = defaults.integer(forKey: "PrisonDisplay.settings." + key)
            return (0..<count).contains(value) ? value : fallback
        }
        mode = index("mode", 2); resolution = index("resolution", 3, compatibilityDefaults ? 1 : 0)
        fps = index("fps", 2, compatibilityDefaults ? 1 : 0); quality = index("quality", VideoQualityProfile.all.count); cursor = index("cursor", 2)
    }
    func save(defaults: UserDefaults = .standard) {
        for (name, value) in [("mode", mode), ("resolution", resolution), ("fps", fps), ("quality", quality), ("cursor", cursor)] {
            defaults.set(value, forKey: "PrisonDisplay.settings." + name)
        }
    }
}

struct ReceiverPreferences: Equatable {
    var keyboard: Bool
    var crossing: Bool
    var edge: Int
    init(defaults: UserDefaults = .standard) {
        keyboard = defaults.bool(forKey: "PrisonDisplay.input.keyboard")
        crossing = defaults.bool(forKey: "PrisonDisplay.input.crossing")
        let stored = defaults.integer(forKey: "desktopEdge")
        edge = (0..<4).contains(stored) ? stored : 0
    }
    func save(defaults: UserDefaults = .standard) {
        defaults.set(keyboard, forKey: "PrisonDisplay.input.keyboard")
        defaults.set(crossing, forKey: "PrisonDisplay.input.crossing")
        defaults.set(edge, forKey: "desktopEdge")
    }
}
