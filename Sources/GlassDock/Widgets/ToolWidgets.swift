import SwiftUI
import AppKit

// MARK: Calculator

/// A small parser, so a typo never reaches NSExpression (which raises instead of failing).
struct MathParser {
    private let chars: [Character]
    private var index = 0

    private init(_ text: String) {
        let normalized = text
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
        chars = Array(normalized.filter { !$0.isWhitespace })
    }

    static func evaluate(_ text: String) -> Double? {
        var parser = MathParser(text)
        guard !parser.chars.isEmpty, let value = parser.expression(), parser.index == parser.chars.count,
              value.isFinite else { return nil }
        return value
    }

    private var current: Character? { index < chars.count ? chars[index] : nil }

    private mutating func expression() -> Double? {
        guard var value = term() else { return nil }
        while let op = current, op == "+" || op == "-" {
            index += 1
            guard let rhs = term() else { return nil }
            value = op == "+" ? value + rhs : value - rhs
        }
        return value
    }

    private mutating func term() -> Double? {
        guard var value = power() else { return nil }
        while let op = current, op == "*" || op == "/" || op == "%" {
            index += 1
            guard let rhs = power() else { return nil }
            switch op {
            case "*": value *= rhs
            case "/": value /= rhs
            default: value = value.truncatingRemainder(dividingBy: rhs)
            }
        }
        return value
    }

    private mutating func power() -> Double? {
        guard let base = unary() else { return nil }
        if current == "^" {
            index += 1
            guard let exponent = power() else { return nil }
            return pow(base, exponent)
        }
        return base
    }

    private mutating func unary() -> Double? {
        if current == "-" {
            index += 1
            return unary().map { -$0 }
        }
        if current == "+" {
            index += 1
            return unary()
        }
        return primary()
    }

    private mutating func primary() -> Double? {
        if current == "(" {
            index += 1
            let value = expression()
            guard current == ")" else { return nil }
            index += 1
            return value
        }
        let start = index
        while let c = current, c.isNumber || c == "." { index += 1 }
        guard index > start else { return nil }
        return Double(String(chars[start..<index]))
    }
}

final class CalculatorWidget: WidgetController {
    @Published var input = ""
    @Published var history: [String] = []

    var result: Double? { MathParser.evaluate(input) }

    func commit() {
        guard let result else { return }
        let text = Fmt.number(result)
        history.insert("\(input) = \(text)", at: 0)
        history = Array(history.prefix(6))
        Clipboard.copy(text)
        input = text
        showFlash("Gekopieerd")
    }

    override func compact(size: CGFloat) -> AnyView {
        AnyView(SymbolCompact(symbol: "plus.forwardslash.minus", size: size))
    }

    override func card() -> AnyView? { AnyView(CalculatorCard(widget: self)) }
}

private struct CalculatorCard: View {
    @ObservedObject var widget: CalculatorWidget

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            TextField("Bijvoorbeeld (12,5 + 3) * 4", text: $widget.input)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14, design: .monospaced))
                .onSubmit { widget.commit() }
            Text(widget.result.map { "= " + Fmt.number($0) } ?? " ")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .textSelection(.enabled)
            if !widget.history.isEmpty {
                Divider()
                ForEach(widget.history, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            Text("Enter kopieert de uitkomst.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(width: 280)
    }
}

// MARK: Color Picker

final class ColorPickerWidget: WidgetController {
    @Published var colors: [String] = [] {
        didSet { store("colors", colors) }
    }
    private var sampler: NSColorSampler?

    required init(id: UUID) {
        super.init(id: id)
        colors = stored("colors", [])
    }

    func pick() {
        CardPresenter.shared.close()
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { [weak self] color in
            Task { @MainActor in
                guard let self else { return }
                self.sampler = nil
                guard let color, let hex = Self.hex(color) else { return }
                Clipboard.copy(hex)
                self.colors.removeAll { $0 == hex }
                self.colors.insert(hex, at: 0)
                self.colors = Array(self.colors.prefix(12))
                self.showFlash(hex)
            }
        }
    }

    static func hex(_ color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()),
                      Int((rgb.blueComponent * 255).rounded()))
    }

    static func color(_ hex: String) -> Color {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        return Color(red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }

    override func tap() -> Bool {
        pick()
        return true
    }

    override func compact(size: CGFloat) -> AnyView { AnyView(ColorPickerCompact(widget: self, size: size)) }
    override func card() -> AnyView? { AnyView(ColorPickerCard(widget: self)) }
}

private struct ColorPickerCompact: View {
    @ObservedObject var widget: ColorPickerWidget
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            SymbolCompact(symbol: "eyedropper", size: size)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let last = widget.colors.first {
                Circle()
                    .fill(ColorPickerWidget.color(last))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
                    .frame(width: size * 0.24, height: size * 0.24)
                    .padding(size * 0.1)
            }
        }
    }
}

private struct ColorPickerCard: View {
    @ObservedObject var widget: ColorPickerWidget

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Kies een kleur van het scherm") { widget.pick() }
                .buttonStyle(PillButtonStyle(prominent: true))
            if widget.colors.isEmpty {
                Text("Nog geen kleuren gekozen.").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 8), count: 4), spacing: 8) {
                    ForEach(widget.colors, id: \.self) { hex in
                        Button {
                            Clipboard.copy(hex)
                            widget.showFlash(hex)
                        } label: {
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(ColorPickerWidget.color(hex))
                                    .frame(height: 34)
                                Text(hex).font(.system(size: 10, design: .monospaced))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("Wis") { widget.colors = [] }
                    .buttonStyle(PillButtonStyle())
            }
        }
        .frame(width: 4 * 64 + 3 * 8, alignment: .leading)
    }
}

// MARK: Clipboard

final class ClipboardWidget: WidgetController {
    @Published var entries: [String] = []
    private var changeCount = NSPasteboard.general.changeCount

    required init(id: UUID) {
        super.init(id: id)
        every(1, fireNow: false) { [weak self] in self?.check() }
    }

    private func check() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        // Password managers mark secrets; never keep those.
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        if pasteboard.types?.contains(concealed) == true { return }
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        entries.removeAll { $0 == text }
        entries.insert(text, at: 0)
        entries = Array(entries.prefix(25))
    }

    func copy(_ text: String) {
        Clipboard.copy(text)
        showFlash("Gekopieerd")
    }

    override func compact(size: CGFloat) -> AnyView { AnyView(ClipboardCompact(widget: self, size: size)) }
    override func card() -> AnyView? { AnyView(ClipboardCard(widget: self)) }
}

private struct ClipboardCompact: View {
    @ObservedObject var widget: ClipboardWidget
    let size: CGFloat

    var body: some View {
        SymbolCompact(symbol: "doc.on.clipboard", size: size, caption: "\(widget.entries.count)")
    }
}

private struct ClipboardCard: View {
    @ObservedObject var widget: ClipboardWidget

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if widget.entries.isEmpty {
                Text("Kopieer iets, dan verschijnt het hier. Alleen in het geheugen, niets wordt bewaard.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(widget.entries, id: \.self) { entry in
                            ClipboardRow(text: entry) {
                                widget.copy(entry)
                                CardPresenter.shared.close()
                            }
                        }
                    }
                }
                .frame(height: 260)
                Button("Wis geschiedenis") { widget.entries = [] }
                    .buttonStyle(PillButtonStyle())
            }
        }
        .frame(width: 320, alignment: .leading)
    }
}

private struct ClipboardRow: View {
    let text: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.12 : 0.05)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
    }
}

// MARK: Password generator

final class GeneratorWidget: WidgetController {
    @Published var length: Double = 20 { didSet { store("length", length) } }
    @Published var symbols = true { didSet { store("symbols", symbols) } }
    @Published var words = false { didSet { store("words", words) } }
    @Published var wordCount: Double = 5 { didSet { store("wordCount", wordCount) } }
    @Published var current = ""

    private static let wordList = [
        "appel", "boom", "wolk", "fiets", "lamp", "regen", "zon", "tafel", "molen", "zee", "berg", "vos",
        "tulp", "kaas", "brug", "haven", "storm", "kompas", "anker", "vlinder", "zilver", "koper", "glas",
        "golf", "duin", "rivier", "lantaarn", "kasteel", "sleutel", "spiegel", "planeet", "komeet", "raket",
        "tijger", "pinguin", "walvis", "koala", "otter", "egel", "uil", "valk", "eekhoorn", "kers", "peer",
        "citroen", "mango", "vijg", "dadel", "honing", "peper", "gember", "kaneel", "munt", "basilicum",
        "winter", "zomer", "lente", "herfst", "noorden", "zuiden", "oosten", "westen", "ster", "maan",
    ]

    required init(id: UUID) {
        super.init(id: id)
        length = stored("length", 20)
        symbols = stored("symbols", true)
        words = stored("words", false)
        wordCount = stored("wordCount", 5)
        current = generate()
    }

    func generate() -> String {
        var rng = SystemRandomNumberGenerator()
        if words {
            let picked = (0..<Int(wordCount)).map { _ in Self.wordList.randomElement(using: &rng) ?? "glas" }
            return picked.joined(separator: "-") + "-" + String(Int.random(in: 10...99, using: &rng))
        }
        var alphabet = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        if symbols { alphabet += Array("!@#$%^&*-_=+?") }
        return String((0..<Int(length)).map { _ in alphabet.randomElement(using: &rng) ?? "x" })
    }

    func regenerate() {
        current = generate()
        Clipboard.copy(current)
        showFlash("Gekopieerd")
    }

    override func tap() -> Bool {
        regenerate()
        return true
    }

    override func compact(size: CGFloat) -> AnyView { AnyView(SymbolCompact(symbol: "key.fill", size: size)) }
    override func card() -> AnyView? { AnyView(GeneratorCard(widget: self)) }
}

private struct GeneratorCard: View {
    @ObservedObject var widget: GeneratorWidget

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(widget.current)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))
            Picker("", selection: $widget.words) {
                Text("Tekens").tag(false)
                Text("Woorden").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if widget.words {
                HStack {
                    Text("\(Int(widget.wordCount)) woorden")
                    Slider(value: $widget.wordCount, in: 3...8, step: 1)
                }
            } else {
                HStack {
                    Text("\(Int(widget.length)) tekens")
                    Slider(value: $widget.length, in: 8...64, step: 1)
                }
                Toggle("Speciale tekens", isOn: $widget.symbols)
            }
            HStack {
                Button("Nieuw en kopieer") { widget.regenerate() }
                    .buttonStyle(PillButtonStyle(prominent: true))
                Button("Kopieer") {
                    Clipboard.copy(widget.current)
                    widget.showFlash("Gekopieerd")
                }
                .buttonStyle(PillButtonStyle())
            }
        }
        .font(.system(size: 12))
        .frame(width: 300)
    }
}

// MARK: Dev servers

struct DevServer: Identifiable, Hashable {
    let port: Int
    let command: String
    let pid: Int32
    var id: Int { port }
}

final class DevServersWidget: WidgetController {
    @Published var servers: [DevServer] = []

    required init(id: UUID) {
        super.init(id: id)
        every(5) { [weak self] in self?.scan() }
    }

    func scan() {
        Task { [weak self] in
            let servers = await Self.listServers()
            if let self, self.servers != servers { self.servers = servers }
        }
    }

    /// Runs lsof off the main thread.
    nonisolated static func listServers() async -> [DevServer] {
        parse(Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"]))
    }

    nonisolated static func parse(_ output: String) -> [DevServer] {
        let ignored: Set<String> = ["rapportd", "ControlCe", "sharingd", "identitys", "Spotify", "Dropbox",
                                    "figma_age", "Adobe", "Creative", "com.docke", "Raycast", "Code\\x20H"]
        var byPort: [Int: DevServer] = [:]
        for line in output.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 10, let pid = Int32(columns[1]) else { continue }
            let name = columns[columns.count - 2]
            guard let colon = name.lastIndex(of: ":"), let port = Int(name[name.index(after: colon)...]),
                  (1024...49151).contains(port) else { continue }
            let command = String(columns[0])
            if ignored.contains(where: { command.hasPrefix($0) }) { continue }
            byPort[port] = DevServer(port: port, command: command.replacingOccurrences(of: "\\x20", with: " "), pid: pid)
        }
        return byPort.values.sorted { $0.port < $1.port }
    }

    func stop(_ server: DevServer) {
        kill(server.pid, SIGTERM)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self?.scan()
        }
    }

    override func compact(size: CGFloat) -> AnyView { AnyView(DevServersCompact(widget: self, size: size)) }
    override func card() -> AnyView? { AnyView(DevServersCard(widget: self)) }
}

private struct DevServersCompact: View {
    @ObservedObject var widget: DevServersWidget
    let size: CGFloat

    var body: some View {
        SymbolCompact(symbol: "server.rack", size: size, tint: widget.servers.isEmpty ? .secondary : .green,
                      caption: widget.servers.isEmpty ? "Geen" : "\(widget.servers.count) actief")
    }
}

private struct DevServersCard: View {
    @ObservedObject var widget: DevServersWidget

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if widget.servers.isEmpty {
                Text("Er luistert nu geen lokale server.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(widget.servers) { server in
                HStack(spacing: 8) {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("localhost:\(server.port)").font(.system(size: 13, weight: .semibold, design: .monospaced))
                        Text("\(server.command) · pid \(server.pid)").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open") {
                        NSWorkspaceBridge.open("http://localhost:\(server.port)")
                        CardPresenter.shared.close()
                    }
                    .buttonStyle(PillButtonStyle())
                    Button { widget.stop(server) } label: { Image(systemName: "stop.fill") }
                        .buttonStyle(RoundIconButtonStyle(size: 26))
                        .help("Stop dit proces")
                }
            }
            Divider()
            Button("Ververs") { widget.scan() }
                .buttonStyle(PillButtonStyle())
        }
        .frame(width: 320, alignment: .leading)
    }
}
