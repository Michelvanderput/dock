import Foundation

/// Hides the macOS Dock while GlassDock runs and puts the user's own settings back on quit.
enum SystemDock {
    private static let backupKey = "systemDockBackup"
    private static let finderPath = "/System/Library/CoreServices/Finder.app"

    static var isHidden: Bool { UserDefaults.standard.dictionary(forKey: backupKey) != nil }

    static func hide() {
        if !isHidden {
            let dock = UserDefaults(suiteName: "com.apple.dock")
            var backup: [String: Any] = ["saved": true]
            if let value = dock?.object(forKey: "autohide") { backup["autohide"] = value }
            if let value = dock?.object(forKey: "autohide-delay") { backup["autohide-delay"] = value }
            UserDefaults.standard.set(backup, forKey: backupKey)
        }
        Shell.run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", "true"])
        Shell.run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide-delay", "-float", "1000"])
        Shell.run("/usr/bin/killall", ["Dock"])
    }

    static func restore() {
        guard let backup = UserDefaults.standard.dictionary(forKey: backupKey) else { return }
        if let autohide = backup["autohide"] as? NSNumber {
            Shell.run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", autohide.boolValue ? "true" : "false"])
        } else {
            Shell.run("/usr/bin/defaults", ["delete", "com.apple.dock", "autohide"])
        }
        if let delay = backup["autohide-delay"] as? NSNumber {
            Shell.run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide-delay", "-float", String(delay.doubleValue)])
        } else {
            Shell.run("/usr/bin/defaults", ["delete", "com.apple.dock", "autohide-delay"])
        }
        UserDefaults.standard.removeObject(forKey: backupKey)
        Shell.run("/usr/bin/killall", ["Dock"])
    }

    /// The apps the user already keeps in the macOS Dock, Finder first.
    static func importPinnedApps() -> [String] {
        var paths: [String] = []
        let dock = UserDefaults(suiteName: "com.apple.dock")
        if let apps = dock?.array(forKey: "persistent-apps") as? [[String: Any]] {
            for entry in apps {
                guard let tile = entry["tile-data"] as? [String: Any],
                      let file = tile["file-data"] as? [String: Any],
                      let string = file["_CFURLString"] as? String else { continue }
                let url = URL(string: string) ?? URL(fileURLWithPath: string)
                let path = url.standardizedFileURL.path
                if FileManager.default.fileExists(atPath: path), !paths.contains(path) {
                    paths.append(path)
                }
            }
        }
        if paths.isEmpty {
            let defaults = ["com.apple.Safari", "com.apple.mail", "com.apple.iCal", "com.apple.Music",
                            "com.apple.Notes", "com.apple.systempreferences"]
            for id in defaults {
                if let url = NSWorkspaceBridge.url(forBundleID: id) { paths.append(url.standardizedFileURL.path) }
            }
        }
        paths.removeAll { $0 == finderPath }
        paths.insert(finderPath, at: 0)
        return paths
    }
}
