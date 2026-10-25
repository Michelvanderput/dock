import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        CardPresenter.shared.close()
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(settings: .shared))
            let window = NSWindow(contentViewController: controller)
            window.title = "GlassDock"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 780, height: 560))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case dock, widgets, general, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dock: return "Dock"
        case .widgets: return "Widgets"
        case .general: return "Algemeen"
        case .about: return "Over"
        }
    }

    var symbol: String {
        switch self {
        case .dock: return "dock.rectangle"
        case .widgets: return "square.grid.2x2"
        case .general: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: DockSettings
    @State private var tab: SettingsTab? = .dock

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $tab) { tab in
                Label(tab.title, systemImage: tab.symbol).tag(Optional(tab))
            }
            .navigationSplitViewColumnWidth(170)
        } detail: {
            switch tab ?? .dock {
            case .dock: DockPane(settings: settings)
            case .widgets: WidgetsPane(settings: settings)
            case .general: GeneralPane(settings: settings)
            case .about: AboutPane()
            }
        }
        .frame(minWidth: 720, minHeight: 500)
    }
}

// MARK: Dock

private struct DockPane: View {
    @ObservedObject var settings: DockSettings

    var body: some View {
        Form {
            Section("Grootte") {
                LabeledContent("Icoongrootte") {
                    Slider(value: $settings.config.iconSize, in: 32...96, step: 1)
                }
                Toggle("Vergroting: iconen groeien onder de aanwijzer", isOn: $settings.config.magnification)
                LabeledContent("Vergroot formaat") {
                    Slider(value: $settings.config.magnifiedSize, in: 40...160, step: 1)
                }
                .disabled(!settings.config.magnification)
                LabeledContent("Afstand tot de rand") {
                    Slider(value: $settings.config.bottomOffset, in: 0...24, step: 1)
                }
            }
            Section("Apps") {
                Toggle("Toon een stip onder geopende apps", isOn: $settings.config.showIndicators)
                Toggle("Toon apps die open zijn maar niet in de Dock staan", isOn: $settings.config.showRecents)
                Toggle("Laat apps stuiteren bij het openen", isOn: $settings.config.bounceOnLaunch)
                Toggle("Toon de map Downloads", isOn: $settings.config.showDownloads)
            }
            Section("Apps in de Dock") {
                ForEach(Array(settings.config.pinnedApps.enumerated()), id: \.element) { index, path in
                    HStack {
                        Image(nsImage: IconCache.icon(for: path))
                            .resizable()
                            .frame(width: 22, height: 22)
                        Text(FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: ""))
                        Spacer()
                        Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(index == 0)
                        Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(index == settings.config.pinnedApps.count - 1)
                        Button { settings.config.pinnedApps.remove(at: index) } label: { Image(systemName: "minus.circle") }
                    }
                    .buttonStyle(.borderless)
                }
                Button("App toevoegen…") { addApp() }
                Text("Tip: sleep een app naar de Dock om hem toe te voegen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard settings.config.pinnedApps.indices.contains(target) else { return }
        settings.config.pinnedApps.swapAt(index, target)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let path = url.standardizedFileURL.path
            if !settings.config.pinnedApps.contains(path) { settings.config.pinnedApps.append(path) }
        }
    }
}

// MARK: Widgets

private struct WidgetsPane: View {
    @ObservedObject var settings: DockSettings

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Form {
                Section("In je Dock") {
                    if settings.config.widgets.isEmpty {
                        Text("Nog geen widgets. Voeg er rechts een toe.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(settings.config.widgets.enumerated()), id: \.element.id) { index, item in
                        HStack {
                            Image(systemName: item.kind.symbol).frame(width: 20)
                            Text(item.kind.title)
                            Spacer()
                            Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                                .disabled(index == 0)
                            Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                                .disabled(index == settings.config.widgets.count - 1)
                            Button { settings.removeWidget(item.id) } label: { Image(systemName: "minus.circle") }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Section("Kant-en-klare Docks") {
                    ForEach(WidgetPreset.allCases) { preset in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(preset.title)
                                Text(preset.kinds.map(\.title).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Gebruik") { settings.config.widgets = preset.items }
                        }
                    }
                }
                Section("Als ze niet passen") {
                    Picker("Toon", selection: $settings.config.overflow) {
                        ForEach(WidgetOverflow.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper("Maximaal \(settings.config.widgetsPerPage) tegelijk",
                            value: $settings.config.widgetsPerPage, in: 1...20)
                    Picker("Plaats", selection: $settings.config.placement) {
                        ForEach(WidgetPlacement.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 320)

            Form {
                ForEach(WidgetCategory.allCases) { category in
                    Section(category.title) {
                        ForEach(WidgetKind.allCases.filter { $0.category == category }) { kind in
                            HStack(alignment: .top) {
                                Image(systemName: kind.symbol).frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kind.title)
                                    Text(kind.summary).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { settings.addWidget(kind) } label: { Image(systemName: "plus.circle.fill") }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 280)
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard settings.config.widgets.indices.contains(target) else { return }
        settings.config.widgets.swapAt(index, target)
    }
}

// MARK: General

private struct GeneralPane: View {
    @ObservedObject var settings: DockSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Verberg de macOS-Dock zolang GlassDock draait", isOn: $settings.config.hideSystemDock)
                Text("Bij het stoppen van GlassDock komt je eigen Dock terug, met je eigen instellingen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Start GlassDock bij het inloggen", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in LaunchAtLogin.set(enabled) }
            }
            Section("Toestemmingen") {
                Text("Sommige widgets vragen eenmalig toestemming: Agenda (Hierna), Automatisering (Speelt nu, Weergave, Prullenmand legen) en Toegankelijkheid (Vergrendel).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Privacy en beveiliging") {
                    NSWorkspaceBridge.open("x-apple.systempreferences:com.apple.preference.security")
                }
            }
            Section {
                Button("Stop GlassDock") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutPane: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "dock.rectangle")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("GlassDock").font(.title.bold())
            Text("Versie \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .foregroundStyle(.secondary)
            Text("Je Dock, met widgets. Een glazen Dock met live widgets naast je apps.\nKlik voor de snelle taak van een widget, houd ingedrukt voor de kaart.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Geïnspireerd door Glasswave Dock. Geen account, geen tracking.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
