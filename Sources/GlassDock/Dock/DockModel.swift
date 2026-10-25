import AppKit
import Combine

struct DockApp: Equatable {
    let path: String
    let name: String
    var isRunning: Bool
    var isPinned: Bool

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }

    init(path: String, isRunning: Bool, isPinned: Bool) {
        self.path = path
        self.name = FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
        self.isRunning = isRunning
        self.isPinned = isPinned
    }
}

enum DockItem: Identifiable {
    case app(DockApp)
    case separator(String)
    case widget(WidgetItem)
    case stack([WidgetItem])
    case pager(page: Int, count: Int)
    case folder
    case trash

    var id: String {
        switch self {
        case .app(let app): return "app:" + app.path
        case .separator(let id): return "sep:" + id
        case .widget(let item): return "widget:" + item.id.uuidString
        case .stack: return "stack"
        case .pager: return "pager"
        case .folder: return "folder"
        case .trash: return "trash"
        }
    }

    /// Only icons grow under the pointer; widgets keep their size so they stay readable.
    var magnifies: Bool {
        switch self {
        case .app, .folder, .trash, .stack: return true
        default: return false
        }
    }

    var label: String? {
        switch self {
        case .app(let app): return app.name
        case .widget(let item): return item.kind.title
        case .stack(let items): return "\(items.count) widgets"
        case .pager: return "Volgende widgets"
        case .folder: return "Downloads"
        case .trash: return "Prullenmand"
        case .separator: return nil
        }
    }
}

@MainActor
final class HoverState: ObservableObject {
    @Published var x: CGFloat?
}

@MainActor
final class DockModel: ObservableObject {
    @Published private(set) var items: [DockItem] = []
    @Published private(set) var launching: Set<String> = []
    @Published var widgetPage = 0 {
        didSet { rebuild() }
    }

    let downloads: FolderModel
    private var bag = Set<AnyCancellable>()

    init() {
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        downloads = FolderModel(url: downloadsURL)

        let center = NSWorkspace.shared.notificationCenter
        Publishers.Merge(
            center.publisher(for: NSWorkspace.didLaunchApplicationNotification),
            center.publisher(for: NSWorkspace.didTerminateApplicationNotification)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] note in self?.appsChanged(note) }
        .store(in: &bag)

        DockSettings.shared.$config
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &bag)

        rebuild()
    }

    private func appsChanged(_ note: Notification) {
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           let url = app.bundleURL {
            launching.remove(url.standardizedFileURL.path)
        }
        rebuild()
    }

    func rebuild() {
        let config = DockSettings.shared.config

        var running: [String: NSRunningApplication] = [:]
        let regular = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        for app in regular {
            if let url = app.bundleURL { running[url.standardizedFileURL.path] = app }
        }

        let pinnedPaths = config.pinnedApps.filter { FileManager.default.fileExists(atPath: $0) }
        let pinnedSet = Set(pinnedPaths)
        var appItems: [DockItem] = pinnedPaths.map {
            .app(DockApp(path: $0, isRunning: running[$0] != nil, isPinned: true))
        }

        if config.showRecents {
            let recents = regular
                .compactMap { app -> (String, Date)? in
                    guard let path = app.bundleURL?.standardizedFileURL.path, !pinnedSet.contains(path) else { return nil }
                    return (path, app.launchDate ?? .distantPast)
                }
                .sorted { $0.1 < $1.1 }
                .map { DockItem.app(DockApp(path: $0.0, isRunning: true, isPinned: false)) }
            if !recents.isEmpty {
                appItems.append(.separator("recents"))
                appItems += recents
            }
        }

        let widgets = config.widgets
        let perPage = max(1, config.widgetsPerPage)
        var widgetItems: [DockItem] = []
        if widgets.count > perPage {
            switch config.overflow {
            case .pages:
                let pages = Int((Double(widgets.count) / Double(perPage)).rounded(.up))
                let page = min(widgetPage, pages - 1)
                let start = page * perPage
                widgetItems = widgets[start..<min(widgets.count, start + perPage)].map { .widget($0) }
                widgetItems.append(.pager(page: page, count: pages))
            case .stack:
                let visible = max(0, perPage - 1)
                widgetItems = widgets.prefix(visible).map { .widget($0) }
                widgetItems.append(.stack(Array(widgets.dropFirst(visible))))
            }
        } else {
            widgetItems = widgets.map { .widget($0) }
        }

        let first = config.placement == .beforeApps ? widgetItems : appItems
        let second = config.placement == .beforeApps ? appItems : widgetItems
        var result = first
        if !first.isEmpty && !second.isEmpty { result.append(.separator("middle")) }
        result += second
        result.append(.separator("tail"))
        if config.showDownloads { result.append(.folder) }
        result.append(.trash)

        items = result
        WidgetStore.shared.prune(keeping: Set(widgets.map(\.id)))
    }

    // MARK: Actions

    func runningApp(_ app: DockApp) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL.path == app.path }
    }

    func open(_ app: DockApp) {
        Debug.log("open app \(app.path)")
        CardPresenter.shared.close()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, _ in }
        guard !app.isRunning, DockSettings.shared.config.bounceOnLaunch else { return }
        launching.insert(app.path)
        let path = app.path
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            self?.launching.remove(path)
        }
    }

    func hide(_ app: DockApp) { runningApp(app)?.hide() }
    func quit(_ app: DockApp) { runningApp(app)?.terminate() }

    func togglePin(_ app: DockApp) {
        if app.isPinned {
            DockSettings.shared.config.pinnedApps.removeAll { $0 == app.path }
        } else {
            pin(app.url)
        }
    }

    func pin(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !DockSettings.shared.config.pinnedApps.contains(path) else { return }
        DockSettings.shared.config.pinnedApps.append(path)
    }

    func nextPage() {
        guard case .pager(let page, let count)? = items.first(where: { if case .pager = $0 { return true } else { return false } }) else { return }
        widgetPage = (page + 1) % max(count, 1)
    }

    /// Dropping an app on the Dock keeps it there.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.canLoadObject(ofClass: NSURL.self) {
            accepted = true
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                guard let url = (object as? NSURL)?.absoluteURL, url.pathExtension == "app" else { return }
                Task { @MainActor in DockPanelController.shared.model.pin(url) }
            }
        }
        return accepted
    }
}

@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for path: String) -> NSImage {
        if let image = cache[path] { return image }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 256, height: 256)
        cache[path] = image
        return image
    }
}

/// Screen positions of Dock items, so a card can open right above the widget it belongs to.
@MainActor
enum FrameRegistry {
    static var frames: [String: CGRect] = [:]
}
