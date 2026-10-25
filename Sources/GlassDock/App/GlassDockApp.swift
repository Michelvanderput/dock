import AppKit
import Combine
import ServiceManagement

@main
@MainActor
struct GlassDockMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var signalSources: [DispatchSourceSignal] = []
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = DockSettings.shared
        if settings.config.hideSystemDock {
            SystemDock.hide()
        } else if SystemDock.isHidden {
            // Left over from a crash: give the user their Dock back.
            SystemDock.restore()
        }

        settings.$config
            .map(\.hideSystemDock)
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { hide in
                if hide { SystemDock.hide() } else { SystemDock.restore() }
            }
            .store(in: &bag)

        DockPanelController.shared.show()
        Debug.start()
        setUpStatusItem()
        handleTerminationSignals()

        if settings.isFirstLaunch && !Debug.enabled {
            SettingsWindowController.shared.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SystemDock.restore()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    // MARK: Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "GlassDock")
            ?? NSImage(systemSymbolName: "square.bottomhalf.filled", accessibilityDescription: "GlassDock")

        let menu = NSMenu()
        menu.addItem(makeItem("Instellingen…", #selector(openSettings), key: ","))
        menu.addItem(makeItem("Toon of verberg GlassDock", #selector(toggleDock), key: ""))
        menu.addItem(.separator())
        menu.addItem(makeItem("Herstel macOS-Dock", #selector(restoreSystemDock), key: ""))
        menu.addItem(.separator())
        menu.addItem(makeItem("Stop GlassDock", #selector(quit), key: "q"))
        item.menu = menu
        statusItem = item
    }

    private func makeItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func toggleDock() { DockPanelController.shared.toggleVisibility() }
    @objc private func restoreSystemDock() { DockSettings.shared.config.hideSystemDock = false }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Signals

    /// `kill` or a logout sends SIGTERM; route it through terminate so the macOS Dock comes back.
    private func handleTerminationSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                Task { @MainActor in NSApp.terminate(nil) }
            }
            source.resume()
            signalSources.append(source)
        }
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("GlassDock: launch at login failed: \(error.localizedDescription)")
        }
    }
}
