import Foundation
import ServiceManagement

enum AutoLaunchPreference {
    static let key = "PrisonDisplay.startAtLogin"

    // Auto-start is enabled on first launch so a saved display can recover
    // after login. Users can turn it off in the main window at any time.
    static func isEnabled(defaults: UserDefaults = .standard,
                          supportsManagedStartup: Bool = LoginItemManager.supportsSystemManagedStartup) -> Bool {
        guard supportsManagedStartup else { return false }
        return defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }

    static func save(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: key)
    }
}

enum LoginItemState: Equatable {
    case enabled
    case approvalRequired
    case disabled
}

enum LoginItemManager {
    static var supportsSystemManagedStartup: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    static func state(supportsManagedStartup: Bool = LoginItemManager.supportsSystemManagedStartup) -> LoginItemState {
        guard supportsManagedStartup else { return .disabled }
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled: return .enabled
            case .requiresApproval: return .approvalRequired
            case .notRegistered, .notFound: return .disabled
            @unknown default: return .disabled
            }
        }
        // LSSharedFileList is deprecated and crashes in some Intel-era macOS
        // releases when queried during app launch. Those systems use the
        // user's Login Items list in System Preferences instead.
        return .disabled
    }

    static func setEnabled(_ enabled: Bool,
                           supportsManagedStartup: Bool = LoginItemManager.supportsSystemManagedStartup) throws -> LoginItemState {
        guard supportsManagedStartup else {
            throw NSError(domain: "PRISON DISPLAY", code: 5, userInfo: [NSLocalizedDescriptionKey: "En macOS anterior a Ventura, configura el inicio desde Preferencias del Sistema → Usuarios y grupos → Ítems de inicio."])
        }
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            if enabled {
                switch service.status {
                case .enabled: return .enabled
                case .requiresApproval: return .approvalRequired
                // notFound refers to the service registration, not the app's
                // filesystem path. Attempt registration and report its real error.
                case .notFound, .notRegistered: try service.register()
                @unknown default: try service.register()
                }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
            let result = state()
            if enabled && result == .disabled {
                throw NSError(domain: "PRISON DISPLAY", code: 1, userInfo: [NSLocalizedDescriptionKey: "macOS no ha confirmado el inicio automático. Revisa General → Ítems de inicio."])
            }
            return result
        }
        return .disabled
    }
}

// Before macOS 13 there is no supported login-item API (LSSharedFileList
// crashes on some Intel releases), so the app opens itself at login with a
// per-user launch agent: `open` on this app's own bundle. It is written only
// when the user turns the option on, and removed when it is turned off.
enum LegacyLoginAgent {
    static var directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    static func label(identifier: String = Bundle.main.bundleIdentifier ?? "local.prisondisplay") -> String {
        "local.prisondisplay.autostart." + identifier.filter { $0.isLetter || $0.isNumber || $0 == "." }
    }
    static func url(identifier: String = Bundle.main.bundleIdentifier ?? "local.prisondisplay") -> URL {
        directory.appendingPathComponent(label(identifier: identifier) + ".plist")
    }
    static func contents(bundle: URL, identifier: String) -> [String: Any] {
        ["Label": label(identifier: identifier), "ProgramArguments": ["/usr/bin/open", bundle.path], "RunAtLoad": true, "LimitLoadToSessionType": "Aqua"]
    }
    static func isEnabled(identifier: String = Bundle.main.bundleIdentifier ?? "local.prisondisplay") -> Bool {
        FileManager.default.fileExists(atPath: url(identifier: identifier).path)
    }
    // Rewrites the agent when the app has moved, so login opens this copy.
    static func setEnabled(_ enabled: Bool, bundle: URL = Bundle.main.bundleURL, identifier: String = Bundle.main.bundleIdentifier ?? "local.prisondisplay") throws {
        let file = url(identifier: identifier)
        guard enabled else {
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            return
        }
        let data = try PropertyListSerialization.data(fromPropertyList: contents(bundle: bundle, identifier: identifier), format: .xml, options: 0)
        if (try? Data(contentsOf: file)) == data { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
}
