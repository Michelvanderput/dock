import AppKit

/// Right-click menus for the Dock, built in AppKit. SwiftUI context menus did not open reliably
/// in the non-activating Dock panel on macOS 26.
@MainActor
enum DockMenus {
    static func menu(for item: DockItem?, model: DockModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        switch item {
        case .app(let app):
            menu.add(app.isRunning ? "Toon" : "Open") { model.open(app) }
            menu.add("Toon in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
            menu.addItem(.separator())
            menu.add(app.isPinned ? "Verwijder uit Dock" : "Houd in Dock") { model.togglePin(app) }
            if app.isRunning {
                menu.addItem(.separator())
                menu.add("Verberg") { model.hide(app) }
                menu.add("Stop") { model.quit(app) }
            }
        case .widget(let widget):
            menu.add("Toon kaart") { CardPresenter.shared.show(item: widget) }
            menu.add("Verwijder widget") {
                CardPresenter.shared.close()
                DockSettings.shared.removeWidget(widget.id)
            }
            menu.addItem(.separator())
            addCommon(to: menu)
        case .folder:
            menu.add("Open in Finder") { NSWorkspace.shared.open(model.downloads.url) }
        case .trash:
            menu.add("Open") {
                NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash"))
            }
            menu.add("Leeg prullenmand") { Script.run("tell application \"Finder\" to empty trash") }
        default:
            addCommon(to: menu)
            menu.add("Stop GlassDock") { NSApp.terminate(nil) }
        }
        return menu
    }

    private static func addCommon(to menu: NSMenu) {
        let add = NSMenuItem(title: "Widget toevoegen", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for category in WidgetCategory.allCases {
            submenu.addItem(.sectionHeader(title: category.title))
            for kind in WidgetKind.allCases where kind.category == category {
                let item = submenu.add(kind.title) { DockSettings.shared.addWidget(kind) }
                item.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
            }
        }
        add.submenu = submenu
        menu.addItem(add)
        menu.add("Dock-instellingen…") { SettingsWindowController.shared.show() }
    }
}

/// Lets a menu item run a closure.
private final class MenuAction: NSObject {
    let perform: () -> Void
    init(_ perform: @escaping () -> Void) { self.perform = perform }
    @objc func run() { perform() }
}

private extension NSMenu {
    @discardableResult
    func add(_ title: String, _ perform: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(perform)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
        item.target = action
        item.representedObject = action // NSMenuItem holds its target weakly.
        addItem(item)
        return item
    }
}
