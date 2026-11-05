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
                case .notFound: throw NSError(domain: "PRISON DISPLAY", code: 1, userInfo: [NSLocalizedDescriptionKey: "macOS no encuentra esta app en Aplicaciones."])
                case .notRegistered: try service.register()
                @unknown default: try service.register()
                }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
            return state()
        }
        return .disabled
    }
}
