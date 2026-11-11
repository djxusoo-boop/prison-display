#if UNIFIED
import AppKit

// Older copies of this same app (same bundle identifier) left in the
// Applications folders, for example one installed by the package as
// administrator while updates went to the user's own folder. Two copies
// confuse the Dock, Launchpad and login. The app offers to move the old ones
// to the Trash, then puts itself in /Applications so there is only one.
enum OldCopies {
    struct Copy { let url: URL; let version: String }
    static var folders: [URL] {
        [URL(fileURLWithPath: "/Applications", isDirectory: true),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)]
    }
    static func find(identifier: String? = Bundle.main.bundleIdentifier, own: URL = Bundle.main.bundleURL, in folders: [URL] = OldCopies.folders) -> [Copy] {
        guard let identifier = identifier else { return [] }
        let self_ = own.standardizedFileURL.resolvingSymlinksInPath()
        var found: [Copy] = []
        for folder in folders {
            guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for url in items where url.pathExtension == "app" && url.standardizedFileURL.resolvingSymlinksInPath() != self_ {
                guard let bundle = Bundle(url: url), bundle.bundleIdentifier == identifier else { continue }
                found.append(Copy(url: url, version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"))
            }
        }
        return found
    }
    // Where this copy should live once the old ones are gone.
    static func preferredLocation(own: URL = Bundle.main.bundleURL) -> URL? {
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard own.deletingLastPathComponent().standardizedFileURL.path != applications.path,
              FileManager.default.isWritableFile(atPath: applications.path) else { return nil }
        let target = applications.appendingPathComponent(own.lastPathComponent)
        return FileManager.default.fileExists(atPath: target.path) ? nil : target
    }

    // Main thread. Asks once per set of copies; "Ahora no" is remembered.
    static func offerCleanup(defaults: UserDefaults = .standard, window: NSWindow?) {
        guard !TestBuild.active else { return }
        let copies = find()
        guard !copies.isEmpty else { return }
        let key = "PrisonDisplay.oldCopies.declined"
        let signature = copies.map { $0.url.path + "@" + $0.version }.sorted().joined(separator: "|")
        guard defaults.string(forKey: key) != signature else { return }
        let alert = NSAlert()
        alert.messageText = copies.count == 1 ? "Hay una versión antigua de PRISON DISPLAY" : "Hay versiones antiguas de PRISON DISPLAY"
        alert.informativeText = copies.map { "• \($0.version) en \($0.url.deletingLastPathComponent().path)" }.joined(separator: "\n")
            + "\n\nEstás usando la \(AppVersion.current). Para no liarte, la antigua va a la Papelera y esta queda en Aplicaciones. Si macOS pide permiso, acéptalo."
        alert.addButton(withTitle: "Quitar la antigua"); alert.addButton(withTitle: "Ahora no")
        guard alert.runModal() == .alertFirstButtonReturn else { defaults.set(signature, forKey: key); return }
        NSWorkspace.shared.recycle(copies.map { $0.url }) { _, error in
            DispatchQueue.main.async {
                let left = find()
                if !left.isEmpty || error != nil {
                    let failed = NSAlert()
                    failed.messageText = "No se pudo quitar la versión antigua"
                    failed.informativeText = "Arrástrala tú a la Papelera desde la ventana del Finder que se abre ahora."
                    failed.runModal()
                    NSWorkspace.shared.activateFileViewerSelecting(left.map { $0.url })
                    return
                }
                moveIntoApplications()
            }
        }
    }
    // Moves this running copy to /Applications (same disk: a rename) and reopens it.
    static func moveIntoApplications() {
        guard let target = preferredLocation() else { return }
        do {
            try FileManager.default.moveItem(at: Bundle.main.bundleURL, to: target)
            if LegacyLoginAgent.isEnabled() { try? LegacyLoginAgent.setEnabled(true, bundle: target) }
            AppUpdater.relaunch(target)
        } catch { /* Staying where it is still works. */ }
    }
}
#endif
