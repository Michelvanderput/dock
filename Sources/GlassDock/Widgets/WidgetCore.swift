import SwiftUI
import Combine

enum WidgetCategory: String, CaseIterable, Identifiable {
    case time, focus, media, mac, developer, tools
    var id: String { rawValue }

    var title: String {
        switch self {
        case .time: return "Tijd en agenda"
        case .focus: return "Focus"
        case .media: return "Muziek"
        case .mac: return "Je Mac"
        case .developer: return "Developer"
        case .tools: return "Tools"
        }
    }
}

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case clock, upNext, moon, timestamp
    case timer, pomodoro, stopwatch, todo, note, counter, breathe
    case nowPlaying
    case battery, activity, network, storage, keepAwake, lockSleep, appearance
    case devServers
    case calculator, colorPicker, clipboard, generator

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "Klok"
        case .upNext: return "Hierna"
        case .moon: return "Maan"
        case .timestamp: return "Timestamp"
        case .timer: return "Timer"
        case .pomodoro: return "Pomodoro"
        case .stopwatch: return "Stopwatch"
        case .todo: return "To-do"
        case .note: return "Notitie"
        case .counter: return "Teller"
        case .breathe: return "Adem"
        case .nowPlaying: return "Speelt nu"
        case .battery: return "Batterij"
        case .activity: return "Activiteit"
        case .network: return "Netwerk"
        case .storage: return "Opslag"
        case .keepAwake: return "Wakker houden"
        case .lockSleep: return "Vergrendel en sluimer"
        case .appearance: return "Weergave"
        case .devServers: return "Dev-servers"
        case .calculator: return "Rekenmachine"
        case .colorPicker: return "Kleurkiezer"
        case .clipboard: return "Klembord"
        case .generator: return "Wachtwoord"
        }
    }

    var symbol: String {
        switch self {
        case .clock: return "clock"
        case .upNext: return "calendar"
        case .moon: return "moon.stars"
        case .timestamp: return "number"
        case .timer: return "timer"
        case .pomodoro: return "flame"
        case .stopwatch: return "stopwatch"
        case .todo: return "checklist"
        case .note: return "note.text"
        case .counter: return "plusminus"
        case .breathe: return "wind"
        case .nowPlaying: return "music.note"
        case .battery: return "battery.100"
        case .activity: return "cpu"
        case .network: return "network"
        case .storage: return "internaldrive"
        case .keepAwake: return "cup.and.saucer"
        case .lockSleep: return "lock"
        case .appearance: return "circle.lefthalf.filled"
        case .devServers: return "server.rack"
        case .calculator: return "plus.forwardslash.minus"
        case .colorPicker: return "eyedropper"
        case .clipboard: return "doc.on.clipboard"
        case .generator: return "key"
        }
    }

    var category: WidgetCategory {
        switch self {
        case .clock, .upNext, .moon, .timestamp: return .time
        case .timer, .pomodoro, .stopwatch, .todo, .note, .counter, .breathe: return .focus
        case .nowPlaying: return .media
        case .battery, .activity, .network, .storage, .keepAwake, .lockSleep, .appearance: return .mac
        case .devServers: return .developer
        case .calculator, .colorPicker, .clipboard, .generator: return .tools
        }
    }

    var summary: String {
        switch self {
        case .clock: return "Tijd, datum en wereldklokken."
        case .upNext: return "Je volgende afspraak, met een knop om deel te nemen."
        case .moon: return "De maanfase van vandaag."
        case .timestamp: return "Unix-tijd. Klik om te kopiëren."
        case .timer: return "Klik om te starten of te pauzeren."
        case .pomodoro: return "Werk en pauze in rondes."
        case .stopwatch: return "Klik om te starten, met rondetijden."
        case .todo: return "Een korte takenlijst."
        case .note: return "Een snelle notitie."
        case .counter: return "Klik om op te tellen."
        case .breathe: return "Rustig ademen in vier tellen."
        case .nowPlaying: return "Spotify en Apple Music. Klik voor afspelen of pauze."
        case .battery: return "Lading, gezondheid en cycli."
        case .activity: return "Processor en geheugen."
        case .network: return "Up- en downloadsnelheid."
        case .storage: return "Vrije ruimte op je schijf."
        case .keepAwake: return "Klik om je Mac wakker te houden."
        case .lockSleep: return "Scherm uit, sluimer of vergrendel."
        case .appearance: return "Klik om licht en donker te wisselen."
        case .devServers: return "Lokale servers die luisteren, zoals localhost:3000."
        case .calculator: return "Reken snel iets uit."
        case .colorPicker: return "Klik om een kleur van je scherm te pakken."
        case .clipboard: return "Wat je onlangs kopieerde."
        case .generator: return "Klik voor een nieuw wachtwoord op je klembord."
        }
    }

    var widthUnits: CGFloat {
        switch self {
        case .nowPlaying, .upNext: return 2
        default: return 1
        }
    }

    var controllerType: WidgetController.Type {
        switch self {
        case .clock: return ClockWidget.self
        case .upNext: return UpNextWidget.self
        case .moon: return MoonWidget.self
        case .timestamp: return TimestampWidget.self
        case .timer: return TimerWidget.self
        case .pomodoro: return PomodoroWidget.self
        case .stopwatch: return StopwatchWidget.self
        case .todo: return TodoWidget.self
        case .note: return NoteWidget.self
        case .counter: return CounterWidget.self
        case .breathe: return BreatheWidget.self
        case .nowPlaying: return NowPlayingWidget.self
        case .battery: return BatteryWidget.self
        case .activity: return ActivityWidget.self
        case .network: return NetworkWidget.self
        case .storage: return StorageWidget.self
        case .keepAwake: return KeepAwakeWidget.self
        case .lockSleep: return LockSleepWidget.self
        case .appearance: return AppearanceWidget.self
        case .devServers: return DevServersWidget.self
        case .calculator: return CalculatorWidget.self
        case .colorPicker: return ColorPickerWidget.self
        case .clipboard: return ClipboardWidget.self
        case .generator: return GeneratorWidget.self
        }
    }
}

struct WidgetItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: WidgetKind
}

enum WidgetPreset: String, CaseIterable, Identifiable {
    case everyday, developer, productivity, student, systemMonitor
    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyday: return "Alledaags"
        case .developer: return "Developer"
        case .productivity: return "Productiviteit"
        case .student: return "Student"
        case .systemMonitor: return "Systeemmonitor"
        }
    }

    var kinds: [WidgetKind] {
        switch self {
        case .everyday: return [.clock, .upNext, .nowPlaying, .battery, .timer, .note]
        case .developer: return [.devServers, .activity, .timestamp, .clipboard, .colorPicker, .generator]
        case .productivity: return [.upNext, .pomodoro, .todo, .note, .keepAwake, .clock]
        case .student: return [.clock, .upNext, .pomodoro, .todo, .calculator, .breathe]
        case .systemMonitor: return [.activity, .network, .storage, .battery, .keepAwake]
        }
    }

    var items: [WidgetItem] { kinds.map { WidgetItem(kind: $0) } }
}

/// One live widget in the Dock. Subclasses supply the compact view, the card and the click action.
@MainActor
class WidgetController: ObservableObject {
    let id: UUID
    var cancellables = Set<AnyCancellable>()
    /// A short message shown over the tile, like "Gekopieerd".
    @Published var flash: String?

    required init(id: UUID) {
        self.id = id
    }

    func compact(size: CGFloat) -> AnyView { AnyView(EmptyView()) }

    func card() -> AnyView? { nil }

    /// Return true when the click did the widget's quick job; false opens the card.
    func tap() -> Bool { false }

    func teardown() {
        cancellables.removeAll()
    }

    func every(_ interval: TimeInterval, fireNow: Bool = true, _ action: @escaping () -> Void) {
        if fireNow { action() }
        Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in action() }
            .store(in: &cancellables)
    }

    func showFlash(_ text: String) {
        flash = text
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if self?.flash == text { self?.flash = nil }
        }
    }

    // Per-widget storage, so two notes keep their own text.
    func stored<T: Decodable>(_ key: String, _ fallback: T) -> T {
        guard let data = UserDefaults.standard.data(forKey: storageKey(key)),
              let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
        return value
    }

    func store<T: Encodable>(_ key: String, _ value: T) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: storageKey(key))
        }
    }

    private func storageKey(_ key: String) -> String { "widget.\(id.uuidString).\(key)" }
}

@MainActor
final class WidgetStore {
    static let shared = WidgetStore()
    private var controllers: [UUID: WidgetController] = [:]

    func controller(for item: WidgetItem) -> WidgetController {
        if let existing = controllers[item.id] { return existing }
        let controller = item.kind.controllerType.init(id: item.id)
        controllers[item.id] = controller
        return controller
    }

    func prune(keeping ids: Set<UUID>) {
        for (id, controller) in controllers where !ids.contains(id) {
            controller.teardown()
            controllers[id] = nil
        }
    }
}

/// A widget as it sits in the Dock: click for its quick job, press and hold for its card.
struct WidgetCell: View {
    let item: WidgetItem
    let size: CGFloat
    var anchor: String? = nil

    var body: some View {
        let controller = WidgetStore.shared.controller(for: item)
        let units = item.kind.widthUnits
        WidgetTile(width: size * units + (units - 1) * DockLayout.spacing, height: size) {
            controller.compact(size: size)
        }
        .overlay(FlashOverlay(controller: controller, size: size))
        .background {
            if anchor == nil { FrameReporter(id: item.id.uuidString) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Debug.log("tap widget \(item.kind.rawValue)")
            if !controller.tap() { CardPresenter.shared.toggle(item: item, anchor: anchor) }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            CardPresenter.shared.show(item: item, anchor: anchor)
        }
        .contextMenu {
            Button("Toon kaart") { CardPresenter.shared.show(item: item, anchor: anchor) }
            Button("Verwijder widget") {
                CardPresenter.shared.close()
                DockSettings.shared.removeWidget(item.id)
            }
            Divider()
            AddWidgetMenu()
            Button("Dock-instellingen…") { SettingsWindowController.shared.show() }
        }
    }
}

private struct FlashOverlay: View {
    @ObservedObject var controller: WidgetController
    let size: CGFloat

    var body: some View {
        if let text = controller.flash {
            Text(text)
                .font(.system(size: size * 0.15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
                .transition(.opacity)
        }
    }
}
