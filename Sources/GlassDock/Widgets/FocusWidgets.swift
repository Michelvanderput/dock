import SwiftUI
import Combine

// MARK: Timer

final class TimerWidget: WidgetController {
    @Published var duration: TimeInterval = 25 * 60
    @Published var remaining: TimeInterval = 25 * 60
    @Published var running = false
    private var endDate: Date?

    required init(id: UUID) {
        super.init(id: id)
        duration = stored("duration", 25 * 60)
        remaining = duration
        every(0.25, fireNow: false) { [weak self] in self?.tick() }
    }

    private func tick() {
        guard running, let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 {
            reset()
            Alerts.notify("Timer klaar", "\(Fmt.minutes(Int(duration / 60))) zijn voorbij.")
            showFlash("Klaar")
        }
    }

    func toggle() {
        if running {
            running = false
            endDate = nil
        } else {
            endDate = Date().addingTimeInterval(remaining)
            running = true
        }
    }

    func reset() {
        running = false
        endDate = nil
        remaining = duration
    }

    func set(minutes: Int) {
        duration = TimeInterval(minutes * 60)
        store("duration", duration)
        reset()
    }

    override func tap() -> Bool {
        toggle()
        return true
    }

    override func compact(size: CGFloat) -> AnyView { AnyView(TimerCompact(widget: self, size: size)) }
    override func card() -> AnyView? { AnyView(TimerCard(widget: self)) }
}

private struct TimerCompact: View {
    @ObservedObject var widget: TimerWidget
    let size: CGFloat

    var body: some View {
        RingCompact(progress: widget.duration > 0 ? widget.remaining / widget.duration : 0,
                    text: Fmt.clock(widget.remaining), size: size,
                    tint: widget.running ? .orange : .secondary)
    }
}

private struct TimerCard: View {
    @ObservedObject var widget: TimerWidget
    private let presets = [1, 5, 10, 15, 25, 45, 60]

    var body: some View {
        VStack(spacing: 14) {
            Text(Fmt.clock(widget.remaining))
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .monospacedDigit()
            HStack(spacing: 10) {
                Button(widget.running ? "Pauze" : "Start") { widget.toggle() }
                    .buttonStyle(PillButtonStyle(prominent: true))
                Button("Herstel") { widget.reset() }
                    .buttonStyle(PillButtonStyle())
            }
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { minutes in
                    Button("\(minutes)") { widget.set(minutes: minutes) }
                        .buttonStyle(PillButtonStyle(prominent: Int(widget.duration / 60) == minutes))
                }
            }
            Text("minuten").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(width: 320)
    }
}

// MARK: Pomodoro

final class PomodoroWidget: WidgetController {
    enum Phase: String {
        case work, shortBreak, longBreak
        var title: String {
            switch self {
            case .work: return "Focus"
            case .shortBreak: return "Korte pauze"
            case .longBreak: return "Lange pauze"
            }
        }
    }

    @Published var phase: Phase = .work
    @Published var remaining: TimeInterval = 25 * 60
    @Published var running = false
    @Published var completed = 0
    @Published var workMinutes = 25
    @Published var breakMinutes = 5
    private var endDate: Date?

    required init(id: UUID) {
        super.init(id: id)
        workMinutes = stored("work", 25)
        breakMinutes = stored("break", 5)
        remaining = length(of: .work)
        every(0.25, fireNow: false) { [weak self] in self?.tick() }
    }

    func length(of phase: Phase) -> TimeInterval {
        switch phase {
        case .work: return TimeInterval(workMinutes * 60)
        case .shortBreak: return TimeInterval(breakMinutes * 60)
        case .longBreak: return TimeInterval(breakMinutes * 3 * 60)
        }
    }

    private func tick() {
        guard running, let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 {
            if phase == .work {
                completed += 1
                Alerts.notify("Tijd voor pauze", "Goed bezig. Even weg van het scherm.")
            } else {
                Alerts.notify("Pauze voorbij", "Klaar voor de volgende ronde?")
            }
            skip()
        }
    }

    func toggle() {
        if running {
            running = false
            endDate = nil
        } else {
            endDate = Date().addingTimeInterval(remaining)
            running = true
        }
    }

    func skip() {
        running = false
        endDate = nil
        if phase == .work {
            phase = completed > 0 && completed % 4 == 0 ? .longBreak : .shortBreak
        } else {
            phase = .work
        }
        remaining = length(of: phase)
    }

    func reset() {
        running = false
        endDate = nil
        phase = .work
        completed = 0
        remaining = length(of: .work)
    }

    func setLengths(work: Int, rest: Int) {
        workMinutes = work
        breakMinutes = rest
        store("work", work)
        store("break", rest)
        if !running { remaining = length(of: phase) }
    }

    override func tap() -> Bool {
        toggle()
        return true
    }

    override func compact(size: CGFloat) -> AnyView { AnyView(PomodoroCompact(widget: self, size: size)) }
    override func card() -> AnyView? { AnyView(PomodoroCard(widget: self)) }
}

private struct PomodoroCompact: View {
    @ObservedObject var widget: PomodoroWidget
    let size: CGFloat

    var body: some View {
        let total = widget.length(of: widget.phase)
        RingCompact(progress: total > 0 ? widget.remaining / total : 0,
                    text: Fmt.clock(widget.remaining), size: size,
                    tint: widget.phase == .work ? .red : .green)
    }
}

private struct PomodoroCard: View {
    @ObservedObject var widget: PomodoroWidget

    var body: some View {
        VStack(spacing: 12) {
            Text(widget.phase.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(widget.phase == .work ? Color.red : Color.green)
            Text(Fmt.clock(widget.remaining))
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .monospacedDigit()
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < widget.completed % 4 || (widget.completed > 0 && widget.completed % 4 == 0)
                              ? Color.red : Color.primary.opacity(0.2))
                        .frame(width: 8, height: 8)
                }
            }
            HStack(spacing: 10) {
                Button(widget.running ? "Pauze" : "Start") { widget.toggle() }
                    .buttonStyle(PillButtonStyle(prominent: true))
                Button("Sla over") { widget.skip() }
                    .buttonStyle(PillButtonStyle())
                Button("Herstel") { widget.reset() }
                    .buttonStyle(PillButtonStyle())
            }
            Divider()
            Stepper("Focus: \(widget.workMinutes) min", value: Binding(
                get: { widget.workMinutes },
                set: { widget.setLengths(work: $0, rest: widget.breakMinutes) }
            ), in: 5...90, step: 5)
            Stepper("Pauze: \(widget.breakMinutes) min", value: Binding(
                get: { widget.breakMinutes },
                set: { widget.setLengths(work: widget.workMinutes, rest: $0) }
            ), in: 1...30)
            Text("\(widget.completed) rondes voltooid")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .frame(width: 280)
    }
}

// MARK: Stopwatch

final class StopwatchWidget: WidgetController {
    @Published var elapsed: TimeInterval = 0
    @Published var running = false
    @Published var laps: [TimeInterval] = []
    private var startDate: Date?
    private var accumulated: TimeInterval = 0

    required init(id: UUID) {
        super.init(id: id)
        every(0.05, fireNow: false) { [weak self] in
            guard let self, self.running, let start = self.startDate else { return }
            self.elapsed = self.accumulated + Date().timeIntervalSince(start)
        }
    }

    func toggle() {
        if running {
            accumulated += Date().timeIntervalSince(startDate ?? Date())
            elapsed = accumulated
            startDate = nil
            running = false
        } else {
            startDate = Date()
            running = true
        }
    }

    func lap() { laps.insert(elapsed, at: 0) }

    func reset() {
        running = false
        startDate = nil
        accumulated = 0
        elapsed = 0
        laps = []
    }

    static func format(_ t: TimeInterval, hundredths: Bool) -> String {
        let total = Int(t)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        let base = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        return hundredths ? base + String(format: ",%02d", Int((t - Double(total)) * 100)) : base
    }

    override func tap() -> Bool {
        toggle()
        return true
    }

    override func compact(size: CGFloat) -> AnyView { AnyView(StopwatchCompact(widget: self, size: size)) }
    override func card() -> AnyView? { AnyView(StopwatchCard(widget: self)) }
}

private struct StopwatchCompact: View {
    @ObservedObject var widget: StopwatchWidget
    let size: CGFloat

    var body: some View {
        SymbolCompact(symbol: "stopwatch", size: size, tint: widget.running ? .orange : .primary,
                      caption: StopwatchWidget.format(widget.elapsed, hundredths: false))
    }
}

private struct StopwatchCard: View {
    @ObservedObject var widget: StopwatchWidget

    var body: some View {
        VStack(spacing: 12) {
            Text(StopwatchWidget.format(widget.elapsed, hundredths: true))
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .monospacedDigit()
            HStack(spacing: 10) {
                Button(widget.running ? "Stop" : "Start") { widget.toggle() }
                    .buttonStyle(PillButtonStyle(prominent: true))
                Button("Ronde") { widget.lap() }
                    .buttonStyle(PillButtonStyle())
                    .disabled(!widget.running)
                Button("Herstel") { widget.reset() }
                    .buttonStyle(PillButtonStyle())
            }
            if !widget.laps.isEmpty {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(widget.laps.enumerated()), id: \.offset) { index, lap in
                            InfoRow(label: "Ronde \(widget.laps.count - index)",
                                    value: StopwatchWidget.format(lap, hundredths: true))
                        }
                    }
                }
                .frame(height: 120)
            }
        }
        .frame(width: 260)
    }
}

// MARK: To-do

struct TodoItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var done = false
}

final class TodoWidget: WidgetController {
    @Published var items: [TodoItem] = [] {
        didSet { store("items", items) }
    }

    required init(id: UUID) {
        super.init(id: id)
        items = stored("items", [])
    }

    var open: Int { items.filter { !$0.done }.count }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(TodoItem(text: trimmed))
    }

    func toggle(_ item: TodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].done.toggle()
    }

    func remove(_ item: TodoItem) { items.removeAll { $0.id == item.id } }
    func clearDone() { items.removeAll { $0.done } }

    override func compact(size: CGFloat) -> AnyView { AnyView(TodoCompact(widget: self, size: size)) }
    override func card() -> AnyView? { AnyView(TodoCard(widget: self)) }
}

private struct TodoCompact: View {
    @ObservedObject var widget: TodoWidget
    let size: CGFloat

    var body: some View {
        SymbolCompact(symbol: widget.open == 0 ? "checkmark.circle" : "checklist", size: size,
                      caption: widget.open == 0 ? "Klaar" : "\(widget.open) open")
    }
}

private struct TodoCard: View {
    @ObservedObject var widget: TodoWidget
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Nieuwe taak", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    widget.add(draft)
                    draft = ""
                }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(widget.items) { item in
                        TodoRow(item: item, widget: widget)
                    }
                    if widget.items.isEmpty {
                        Text("Nog niets te doen.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 200)
            if widget.items.contains(where: \.done) {
                Button("Wis voltooide taken") { widget.clearDone() }
                    .buttonStyle(PillButtonStyle())
            }
        }
        .font(.system(size: 13))
        .frame(width: 300)
    }
}

private struct TodoRow: View {
    let item: TodoItem
    @ObservedObject var widget: TodoWidget
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button { widget.toggle(item) } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.done ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            Text(item.text)
                .strikethrough(item.done)
                .foregroundStyle(item.done ? .secondary : .primary)
            Spacer()
            if hovering {
                Button { widget.remove(item) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

// MARK: Note

final class NoteWidget: WidgetController {
    @Published var text = "" {
        didSet { store("text", text) }
    }

    required init(id: UUID) {
        super.init(id: id)
        text = stored("text", "")
    }

    override func compact(size: CGFloat) -> AnyView { AnyView(NoteCompact(widget: self, size: size)) }
    override func card() -> AnyView? { AnyView(NoteCard(widget: self)) }
}

private struct NoteCompact: View {
    @ObservedObject var widget: NoteWidget
    let size: CGFloat

    var body: some View {
        if widget.text.isEmpty {
            SymbolCompact(symbol: "note.text", size: size)
        } else {
            Text(widget.text)
                .font(.system(size: size * 0.14))
                .lineLimit(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(size * 0.1)
                .background(Color.yellow.opacity(0.18))
        }
    }
}

private struct NoteCard: View {
    @ObservedObject var widget: NoteWidget

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $widget.text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
                .frame(width: 300, height: 220)
            HStack {
                Text("\(widget.text.count) tekens").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Kopieer") { Clipboard.copy(widget.text) }
                    .buttonStyle(PillButtonStyle())
            }
        }
    }
}

// MARK: Counter

final class CounterWidget: WidgetController {
    @Published var count = 0 {
        didSet { store("count", count) }
    }

    required init(id: UUID) {
        super.init(id: id)
        count = stored("count", 0)
    }

    override func tap() -> Bool {
        count += 1
        return true
    }

    override func compact(size: CGFloat) -> AnyView { AnyView(CounterCompact(widget: self, size: size)) }
    override func card() -> AnyView? { AnyView(CounterCard(widget: self)) }
}

private struct CounterCompact: View {
    @ObservedObject var widget: CounterWidget
    let size: CGFloat

    var body: some View {
        Text("\(widget.count)")
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .padding(size * 0.08)
    }
}

private struct CounterCard: View {
    @ObservedObject var widget: CounterWidget

    var body: some View {
        VStack(spacing: 12) {
            Text("\(widget.count)")
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .monospacedDigit()
            HStack(spacing: 14) {
                Button { widget.count -= 1 } label: { Image(systemName: "minus") }
                    .buttonStyle(RoundIconButtonStyle(size: 40))
                Button { widget.count += 1 } label: { Image(systemName: "plus") }
                    .buttonStyle(RoundIconButtonStyle(size: 40))
            }
            Button("Zet op nul") { widget.count = 0 }
                .buttonStyle(PillButtonStyle())
        }
        .frame(width: 220)
    }
}

// MARK: Breathe

final class BreatheWidget: WidgetController {
    override func compact(size: CGFloat) -> AnyView { AnyView(SymbolCompact(symbol: "wind", size: size, tint: .teal)) }
    override func card() -> AnyView? { AnyView(BreatheCard()) }
}

private struct BreatheCard: View {
    @State private var inhale = false
    @State private var breaths = 0
    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.teal.opacity(0.7), Color.blue.opacity(0.25)],
                                         center: .center, startRadius: 4, endRadius: 90))
                    .frame(width: 170, height: 170)
                    .scaleEffect(inhale ? 1 : 0.45)
                Text(inhale ? "Adem in" : "Adem uit")
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(width: 180, height: 180)
            Text("\(breaths / 2) ademhalingen")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(width: 240)
        .onAppear {
            withAnimation(.easeInOut(duration: 4)) { inhale = true }
        }
        .onReceive(timer) { _ in
            breaths += 1
            withAnimation(.easeInOut(duration: 4)) { inhale.toggle() }
        }
    }
}
