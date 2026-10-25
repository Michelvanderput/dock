import SwiftUI
import EventKit
import AppKit

// MARK: Clock

final class ClockWidget: WidgetController {
    @Published var now = Date()
    struct Zone { let name: String; let id: String }
    let zones = [
        Zone(name: "Londen", id: "Europe/London"), Zone(name: "New York", id: "America/New_York"),
        Zone(name: "Tokio", id: "Asia/Tokyo"),
    ]

    required init(id: UUID) {
        super.init(id: id)
        every(1) { [weak self] in self?.now = Date() }
    }

    override func compact(size: CGFloat) -> AnyView { AnyView(ClockCompact(widget: self, size: size)) }
    override func card() -> AnyView? { AnyView(ClockCard(widget: self)) }
}

private struct ClockCompact: View {
    @ObservedObject var widget: ClockWidget
    let size: CGFloat

    var body: some View {
        VStack(spacing: size * 0.02) {
            Text(Fmt.hm.string(from: widget.now))
                .font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(Fmt.dayShort.string(from: widget.now))
                .font(.system(size: size * 0.16, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(size * 0.06)
    }
}

private struct ClockCard: View {
    @ObservedObject var widget: ClockWidget

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Fmt.hms.string(from: widget.now))
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(Fmt.sentence(Fmt.dayLong.string(from: widget.now)))
                .foregroundStyle(.secondary)
            Divider()
            ForEach(widget.zones, id: \.id) { zone in
                HStack {
                    Text(zone.name)
                    Spacer()
                    Text(offset(zone.id)).foregroundStyle(.secondary).font(.system(size: 11))
                    Text(time(in: zone.id)).monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                .font(.system(size: 13))
            }
        }
        .frame(width: 260)
    }

    private func time(in zone: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = TimeZone(identifier: zone)
        return f.string(from: widget.now)
    }

    private func offset(_ zone: String) -> String {
        guard let tz = TimeZone(identifier: zone) else { return "" }
        let hours = Double(tz.secondsFromGMT(for: widget.now) - TimeZone.current.secondsFromGMT(for: widget.now)) / 3600
        if hours == 0 { return "zelfde tijd" }
        return (hours > 0 ? "+" : "") + Fmt.number(hours, digits: 1) + " u"
    }
}

// MARK: Up Next

final class UpNextWidget: WidgetController {
    enum Access { case unknown, granted, denied }

    @Published var events: [EKEvent] = []
    @Published var access: Access = .unknown
    @Published var now = Date()
    private let store = EKEventStore()

    required init(id: UUID) {
        super.init(id: id)
        requestAccess()
        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
        every(30, fireNow: false) { [weak self] in
            self?.now = Date()
            self?.reload()
        }
    }

    func requestAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
            reload()
        case .denied, .restricted, .writeOnly:
            access = .denied
        default:
            store.requestFullAccessToEvents { [weak self] granted, _ in
                Task { @MainActor in
                    self?.access = granted ? .granted : .denied
                    self?.reload()
                }
            }
        }
    }

    func reload() {
        guard access == .granted else { return }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-6 * 3600),
                                                 end: now.addingTimeInterval(48 * 3600), calendars: nil)
        events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
            .map { $0 }
    }

    var next: EKEvent? { events.first }

    override func tap() -> Bool {
        // Within ten minutes of a call, a click joins it.
        if let event = next, event.startDate.timeIntervalSinceNow < 600, let url = Self.joinURL(event) {
            NSWorkspace.shared.open(url)
            return true
        }
        return false
    }

    override func compact(size: CGFloat) -> AnyView { AnyView(UpNextCompact(widget: self, size: size)) }
    override func card() -> AnyView? { AnyView(UpNextCard(widget: self)) }

    static func relative(_ event: EKEvent, now: Date = Date()) -> String {
        let minutes = Int(event.startDate.timeIntervalSince(now) / 60)
        if event.startDate <= now { return "Nu bezig" }
        if minutes < 60 { return "Over \(max(1, minutes)) min" }
        let calendar = Calendar.current
        if calendar.isDateInToday(event.startDate) { return "Om " + Fmt.hm.string(from: event.startDate) }
        if calendar.isDateInTomorrow(event.startDate) { return "Morgen " + Fmt.hm.string(from: event.startDate) }
        return Fmt.weekdayTime.string(from: event.startDate)
    }

    static func joinURL(_ event: EKEvent) -> URL? {
        var texts: [String] = []
        if let url = event.url { texts.append(url.absoluteString) }
        if let location = event.location { texts.append(location) }
        if let notes = event.notes { texts.append(notes) }
        let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com",
                     "whereby.com", "facetime.apple.com"]
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts {
            for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let url = match.url, let host = url.host?.lowercased(), hosts.contains(where: { host.hasSuffix($0) }) {
                    return url
                }
            }
        }
        return nil
    }
}

private struct UpNextCompact: View {
    @ObservedObject var widget: UpNextWidget
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.12) {
            if let event = widget.next {
                Capsule()
                    .fill(Color(cgColor: event.calendar?.cgColor ?? NSColor.systemBlue.cgColor))
                    .frame(width: size * 0.06, height: size * 0.6)
                VStack(alignment: .leading, spacing: size * 0.03) {
                    Text(event.title ?? "Afspraak")
                        .font(.system(size: size * 0.19, weight: .semibold))
                    Text(UpNextWidget.relative(event, now: widget.now))
                        .font(.system(size: size * 0.16))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            } else {
                Image(systemName: "calendar")
                    .font(.system(size: size * 0.3))
                Text(widget.access == .denied ? "Geef toegang tot Agenda" : "Niets gepland")
                    .font(.system(size: size * 0.16, weight: .medium))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, size * 0.16)
    }
}

private struct UpNextCard: View {
    @ObservedObject var widget: UpNextWidget

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if widget.access == .denied {
                Text("GlassDock heeft geen toegang tot je agenda.")
                    .font(.system(size: 13))
                Button("Open Privacy-instellingen") {
                    NSWorkspaceBridge.open("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
                }
                .buttonStyle(PillButtonStyle(prominent: true))
            } else if let event = widget.next {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title ?? "Afspraak")
                        .font(.system(size: 17, weight: .semibold))
                    Text("\(UpNextWidget.relative(event, now: widget.now)) · \(Fmt.hm.string(from: event.startDate)) – \(Fmt.hm.string(from: event.endDate))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if let location = event.location, !location.isEmpty {
                        Text(location).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if let url = UpNextWidget.joinURL(event) {
                    Button("Neem deel") {
                        NSWorkspace.shared.open(url)
                        CardPresenter.shared.close()
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))
                }
                let later = Array(widget.events.dropFirst())
                if !later.isEmpty {
                    Divider()
                    Text("Later").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(later, id: \.eventIdentifier) { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(cgColor: item.calendar?.cgColor ?? NSColor.systemBlue.cgColor))
                                .frame(width: 7, height: 7)
                            Text(item.title ?? "Afspraak").lineLimit(1)
                            Spacer()
                            Text(UpNextWidget.relative(item, now: widget.now)).foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12))
                    }
                }
            } else {
                Text("Geen afspraken in de komende twee dagen.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button("Open Agenda") {
                NSWorkspaceBridge.openApp(bundleID: "com.apple.iCal")
                CardPresenter.shared.close()
            }
            .buttonStyle(PillButtonStyle())
        }
        .frame(width: 300, alignment: .leading)
    }
}

// MARK: Moon

final class MoonWidget: WidgetController {
    @Published var now = Date()

    required init(id: UUID) {
        super.init(id: id)
        every(600) { [weak self] in self?.now = Date() }
    }

    static let cycle = 29.530588853
    /// A known new moon: 6 January 2000, 18:14 UTC.
    static let reference = Date(timeIntervalSince1970: 947_182_440)

    /// 0 = new moon, 0.5 = full moon.
    static func phase(_ date: Date) -> Double {
        let days = date.timeIntervalSince(reference) / 86400
        let p = days.truncatingRemainder(dividingBy: cycle) / cycle
        return p < 0 ? p + 1 : p
    }

    static func info(_ date: Date) -> (symbol: String, name: String) {
        let names: [(String, String)] = [
            ("moonphase.new.moon", "Nieuwe maan"), ("moonphase.waxing.crescent", "Wassende sikkel"),
            ("moonphase.first.quarter", "Eerste kwartier"), ("moonphase.waxing.gibbous", "Wassende maan"),
            ("moonphase.full.moon", "Volle maan"), ("moonphase.waning.gibbous", "Afnemende maan"),
            ("moonphase.last.quarter", "Laatste kwartier"), ("moonphase.waning.crescent", "Afnemende sikkel"),
        ]
        let index = Int((phase(date) * 8).rounded()) % 8
        return names[index]
    }

    static func days(until target: Double, from date: Date) -> Int {
        var delta = target - phase(date)
        if delta <= 0 { delta += 1 }
        return Int((delta * cycle).rounded())
    }

    override func compact(size: CGFloat) -> AnyView {
        AnyView(MoonCompact(widget: self, size: size))
    }

    override func card() -> AnyView? { AnyView(MoonCard(widget: self)) }
}

private struct MoonCompact: View {
    @ObservedObject var widget: MoonWidget
    let size: CGFloat

    var body: some View {
        SymbolCompact(symbol: MoonWidget.info(widget.now).symbol, size: size,
                      caption: "\(Int(illumination * 100))%")
    }

    private var illumination: Double { (1 - cos(2 * .pi * MoonWidget.phase(widget.now))) / 2 }
}

private struct MoonCard: View {
    @ObservedObject var widget: MoonWidget

    var body: some View {
        let info = MoonWidget.info(widget.now)
        let illumination = (1 - cos(2 * .pi * MoonWidget.phase(widget.now))) / 2
        HStack(spacing: 16) {
            Image(systemName: info.symbol)
                .font(.system(size: 54))
            VStack(alignment: .leading, spacing: 6) {
                Text(info.name).font(.system(size: 16, weight: .semibold))
                InfoRow(label: "Verlicht", value: "\(Int(illumination * 100))%")
                InfoRow(label: "Volle maan", value: "over \(MoonWidget.days(until: 0.5, from: widget.now)) d")
                InfoRow(label: "Nieuwe maan", value: "over \(MoonWidget.days(until: 1.0, from: widget.now)) d")
            }
        }
        .frame(width: 280)
    }
}

// MARK: Timestamp

final class TimestampWidget: WidgetController {
    @Published var now = Date()

    required init(id: UUID) {
        super.init(id: id)
        every(1) { [weak self] in self?.now = Date() }
    }

    var unix: Int { Int(now.timeIntervalSince1970) }

    override func tap() -> Bool {
        Clipboard.copy(String(unix))
        showFlash("Gekopieerd")
        return true
    }

    override func compact(size: CGFloat) -> AnyView { AnyView(TimestampCompact(widget: self, size: size)) }
    override func card() -> AnyView? { AnyView(TimestampCard(widget: self)) }
}

private struct TimestampCompact: View {
    @ObservedObject var widget: TimestampWidget
    let size: CGFloat

    var body: some View {
        VStack(spacing: size * 0.04) {
            Text("UNIX")
                .font(.system(size: size * 0.14, weight: .bold))
                .foregroundStyle(.secondary)
            Text(String(widget.unix))
                .font(.system(size: size * 0.16, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(size * 0.06)
    }
}

private struct TimestampCard: View {
    @ObservedObject var widget: TimestampWidget
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Seconden", String(widget.unix))
            row("Milliseconden", String(Int(widget.now.timeIntervalSince1970 * 1000)))
            row("ISO 8601", ISO8601DateFormatter().string(from: widget.now))
            Divider()
            TextField("Plak een timestamp", text: $input)
                .textFieldStyle(.roundedBorder)
            if let date = converted {
                Text(Fmt.dateTime.string(from: date))
                    .font(.system(size: 13, weight: .medium))
                    .textSelection(.enabled)
            }
        }
        .frame(width: 300)
    }

    private var converted: Date? {
        guard let value = Double(input.trimmingCharacters(in: .whitespaces)) else { return nil }
        // Thirteen digits means milliseconds.
        return Date(timeIntervalSince1970: value > 100_000_000_000 ? value / 1000 : value)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 12, design: .monospaced))
            Button {
                Clipboard.copy(value)
                widget.showFlash("Gekopieerd")
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
        }
        .font(.system(size: 12))
    }
}
