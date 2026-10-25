import Foundation
import Combine

enum WidgetPlacement: String, Codable, CaseIterable, Identifiable {
    case afterApps, beforeApps
    var id: String { rawValue }
    var title: String { self == .afterApps ? "Na de apps (bij de prullenmand)" : "Voor de apps" }
}

enum WidgetOverflow: String, Codable, CaseIterable, Identifiable {
    case pages, stack
    var id: String { rawValue }
    var title: String { self == .pages ? "Per set, met een volgende-knop" : "In een stapel boven de Dock" }
}

struct DockConfig: Codable, Equatable {
    var iconSize: Double = 52
    var magnification = true
    var magnifiedSize: Double = 84
    var showIndicators = true
    var showRecents = true
    var showDownloads = true
    var bounceOnLaunch = true
    var placement: WidgetPlacement = .afterApps
    var overflow: WidgetOverflow = .pages
    var widgetsPerPage = 6
    var hideSystemDock = true
    var bottomOffset: Double = 6
    var pinnedApps: [String] = []
    var widgets: [WidgetItem] = WidgetPreset.everyday.items

    init() {}

    // Decode field by field so settings from older versions keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DockConfig()
        iconSize = try c.decodeIfPresent(Double.self, forKey: .iconSize) ?? d.iconSize
        magnification = try c.decodeIfPresent(Bool.self, forKey: .magnification) ?? d.magnification
        magnifiedSize = try c.decodeIfPresent(Double.self, forKey: .magnifiedSize) ?? d.magnifiedSize
        showIndicators = try c.decodeIfPresent(Bool.self, forKey: .showIndicators) ?? d.showIndicators
        showRecents = try c.decodeIfPresent(Bool.self, forKey: .showRecents) ?? d.showRecents
        showDownloads = try c.decodeIfPresent(Bool.self, forKey: .showDownloads) ?? d.showDownloads
        bounceOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .bounceOnLaunch) ?? d.bounceOnLaunch
        placement = (try? c.decodeIfPresent(WidgetPlacement.self, forKey: .placement)) ?? d.placement
        overflow = (try? c.decodeIfPresent(WidgetOverflow.self, forKey: .overflow)) ?? d.overflow
        widgetsPerPage = try c.decodeIfPresent(Int.self, forKey: .widgetsPerPage) ?? d.widgetsPerPage
        hideSystemDock = try c.decodeIfPresent(Bool.self, forKey: .hideSystemDock) ?? d.hideSystemDock
        bottomOffset = try c.decodeIfPresent(Double.self, forKey: .bottomOffset) ?? d.bottomOffset
        pinnedApps = try c.decodeIfPresent([String].self, forKey: .pinnedApps) ?? d.pinnedApps
        widgets = (try? c.decodeIfPresent([WidgetItem].self, forKey: .widgets)) ?? d.widgets
    }
}

@MainActor
final class DockSettings: ObservableObject {
    static let shared = DockSettings()
    private static let key = "dockConfig"

    let isFirstLaunch: Bool
    @Published var config: DockConfig {
        didSet { if config != oldValue { persist() } }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(DockConfig.self, from: data) {
            config = saved
            isFirstLaunch = false
        } else {
            var fresh = DockConfig()
            fresh.pinnedApps = SystemDock.importPinnedApps()
            config = fresh
            isFirstLaunch = true
            persist()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func addWidget(_ kind: WidgetKind) {
        config.widgets.append(WidgetItem(kind: kind))
    }

    func removeWidget(_ id: UUID) {
        config.widgets.removeAll { $0.id == id }
    }
}
