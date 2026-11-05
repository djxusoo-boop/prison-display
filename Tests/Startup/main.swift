import Foundation

let suite = "PrisonDisplayStartupTests." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }

precondition(AutoLaunchPreference.isEnabled(defaults: defaults) == LoginItemManager.supportsSystemManagedStartup,
       "first launch only enables managed startup on macOS 13 and later")
AutoLaunchPreference.save(false, defaults: defaults)
precondition(!AutoLaunchPreference.isEnabled(defaults: defaults), "user can disable startup")
AutoLaunchPreference.save(true, defaults: defaults)
precondition(AutoLaunchPreference.isEnabled(defaults: defaults) == LoginItemManager.supportsSystemManagedStartup,
       "startup remains unsupported on legacy macOS even if an old preference was saved")
precondition(!AutoLaunchPreference.isEnabled(defaults: defaults, supportsManagedStartup: false),
       "legacy systems do not trigger automatic login-item inspection")
precondition(LoginItemManager.state(supportsManagedStartup: false) == .disabled,
       "legacy startup status does not query LSSharedFileList")
do {
    _ = try LoginItemManager.setEnabled(true, supportsManagedStartup: false)
    preconditionFailure("legacy systems must not call the deprecated login-item API")
} catch let error as NSError {
    precondition(error.code == 5, "legacy startup explains the manual System Preferences path")
}
print("PASS: startup preference follows supported macOS behavior without legacy LSSharedFileList access")
