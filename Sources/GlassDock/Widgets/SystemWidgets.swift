import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import Darwin

// MARK: Battery

struct BatteryInfo: Equatable {
    var hasBattery = false
    var percent = 0
    var charging = false
    var onPower = true
    var minutesToEmpty: Int?
    var minutesToFull: Int?
    var cycles: Int?
    var health: Int?
    var temperature: Double?

    static func read() -> BatteryInfo {
        var info = BatteryInfo()
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                      description["Type"] as? String == "InternalBattery" else { continue }
                info.hasBattery = true
                let current = description["Current Capacity"] as? Int ?? 0
                let max = description["Max Capacity"] as? Int ?? 100
                info.percent = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
                info.charging = description["Is Charging"] as? Bool ?? false
                info.onPower = description["Power Source State"] as? String == "AC Power"
                if let t = description["Time to Empty"] as? Int, t > 0 { info.minutesToEmpty = t }
                if let t = description["Time to Full Charge"] as? Int, t > 0 { info.minutesToFull = t }
            }
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            info.cycles = property("CycleCount") as? Int
            if let raw = (property("AppleRawMaxCapacity") ?? property("NominalChargeCapacity")) as? Int,
               let design = property("DesignCapacity") as? Int, design > 0 {
                info.health = min(100, Int((Double(raw) / Double(design) * 100).rounded()))
            }
            if let t = property("Temperature") as? Int { info.temperature = Double(t) / 100 }
            IOObjectRelease(service)
        }
        return info
    }

    var symbol: String {
        if !hasBattery { return "powerplug" }
        if charging { return "battery.100.bolt" }
        switch percent {
        case 88...: return "battery.100"
        case 63..<88: return "battery.75"
        case 38..<63: return "battery.50"
        case 13..<38: return "battery.25"
        default: return "battery.0"
        }
    }

    var status: String {
        if !hasBattery { return "Op netstroom" }
        if charging {
            if let m = minutesToFull { return "Wordt opgeladen, vol over \(Fmt.minutes(m))" }
            return "Wordt opgeladen"
        }
        if onPower { return percent >= 99 ? "Opgeladen" : "Op netstroom, laden gepauzeerd" }
        if let m = minutesToEmpty { return "Op batterij, nog ongeveer \(Fmt.minutes(m))" }
        return "Op batterij"
    }
}

final class BatteryWidget: WidgetController {
    @Published var info = BatteryInfo()

    required init(id: UUID) {
        super.init(id: id)
        every(30) { [weak self] in self?.info = BatteryInfo.read() }
    }

    override func compact(size: CGFloat) -> AnyView { AnyView(BatteryCompact(widget: self, size: size)) }
    override func card() -> AnyView? { AnyView(BatteryCard(widget: self)) }
}

private struct BatteryCompact: View {
    @ObservedObject var widget: BatteryWidget
    let size: CGFloat

    var body: some View {
        let info = widget.info
        SymbolCompact(symbol: info.symbol, size: size,
                      tint: info.hasBattery && info.percent <= 20 && !info.charging ? .red : (info.charging ? .green : .primary),
                      caption: info.hasBattery ? "\(info.percent)%" : "AC")
    }
}

private struct BatteryCard: View {
    @ObservedObject var widget: BatteryWidget

    var body: some View {
        let info = widget.info
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(info.hasBattery ? "\(info.percent)%" : "Geen batterij")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                Image(systemName: info.symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(info.charging ? .green : .primary)
            }
            Text(info.status).font(.system(size: 12)).foregroundStyle(.secondary)
            if info.hasBattery {
                ProgressView(value: Double(info.percent), total: 100)
                    .tint(info.percent <= 20 ? .red : .green)
                Divider()
                if let health = info.health { InfoRow(label: "Capaciteit", value: "\(health)%") }
                if let cycles = info.cycles { InfoRow(label: "Cycli", value: "\(cycles)") }
                if let health = info.health {
                    InfoRow(label: "Conditie", value: health >= 80 ? "Normaal" : "Onderhoud aanbevolen")
                }
                if let t = info.temperature { InfoRow(label: "Temperatuur", value: Fmt.number(t, digits: 1) + " °C") }
            }
            Button("Batterij-instellingen") {
                NSWorkspaceBridge.open("x-apple.systempreferences:com.apple.Battery-Settings.extension")
            }
            .buttonStyle(PillButtonStyle())
        }
        .frame(width: 260, alignment: .leading)
    }
}

// MARK: Activity

final class ActivityWidget: WidgetController {
    @Published var cpu: Double = 0
    @Published var cpuHistory: [Double] = []
    @Published var memoryUsed: UInt64 = 0
    let memoryTotal = ProcessInfo.processInfo.physicalMemory
    private var lastTicks: (busy: UInt64, total: UInt64)?

    required init(id: UUID) {
        super.init(id: id)
        every(2) { [weak self] in self?.sample() }
    }

    var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }

    private func sample() {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let user = UInt64(load.cpu_ticks.0), system = UInt64(load.cpu_ticks.1)
            let idle = UInt64(load.cpu_ticks.2), nice = UInt64(load.cpu_ticks.3)
            let busy = user + system + nice
            let total = busy + idle
            if let last = lastTicks, total > last.total {
                cpu = Double(busy - last.busy) / Double(total - last.total)
                cpuHistory = Array((cpuHistory + [cpu]).suffix(40))
            }
            lastTicks = (busy, total)
        }

        var stats = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let vmResult = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
            }
        }
        if vmResult == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let appMemory = UInt64(stats.internal_page_count) - min(UInt64(stats.internal_page_count), UInt64(stats.purgeable_count))
            memoryUsed = (appMemory + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        }
    }

    override func compact(size: CGFloat) -> AnyView { AnyView(ActivityCompact(widget: self, size: size)) }
    override func card() -> AnyView? { AnyView(ActivityCard(widget: self)) }
}

private struct ActivityCompact: View {
    @ObservedObject var widget: ActivityWidget
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.08) {
            bar("CPU", widget.cpu, .blue)
            bar("RAM", widget.memoryFraction, .purple)
        }
        .padding(.horizontal, size * 0.12)
    }

    private func bar(_ label: String, _ value: Double, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Text(label).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(Int(value * 100))%").monospacedDigit()
            }
            .font(.system(size: size * 0.14, weight: .semibold))
            GeometryReader { geo in
                Capsule().fill(Color.primary.opacity(0.15))
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint).frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
                    }
            }
            .frame(height: size * 0.06)
        }
    }
}

private struct ActivityCard: View {
    @ObservedObject var widget: ActivityWidget

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Processor").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Int(widget.cpu * 100))%").monospacedDigit()
            }
            Sparkline(values: widget.cpuHistory, maxValue: 1, tint: .blue)
                .frame(height: 50)
            Divider()
            InfoRow(label: "Geheugen in gebruik", value: Fmt.bytes(Int64(widget.memoryUsed)))
            InfoRow(label: "Totaal geheugen", value: Fmt.bytes(Int64(widget.memoryTotal)))
            ProgressView(value: widget.memoryFraction).tint(.purple)
            InfoRow(label: "Kernen", value: "\(ProcessInfo.processInfo.activeProcessorCount)")
            InfoRow(label: "Aan sinds", value: Fmt.minutes(Int(ProcessInfo.processInfo.systemUptime / 60)))
            Button("Open Activiteitenweergave") {
                NSWorkspaceBridge.openApp(bundleID: "com.apple.ActivityMonitor")
                CardPresenter.shared.close()
            }
            .buttonStyle(PillButtonStyle())
        }
        .font(.system(size: 12))
        .frame(width: 280)
    }
}

// MARK: Network

final class NetworkWidget: WidgetController {
    @Published var down: Double = 0
    @Published var up: Double = 0
    @Published var history: [Double] = []
    @Published var address = "–"
    private var last: (input: UInt64, output: UInt64, date: Date)?

    required init(id: UUID) {
        super.init(id: id)
        every(2) { [weak self] in self?.sample() }
    }

    private func sample() {
        var input: UInt64 = 0, output: UInt64 = 0
        var ipv4: String?
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return }
        defer { freeifaddrs(pointer) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let ifa = entry.pointee
            let name = String(cString: ifa.ifa_name)
            if let addr = ifa.ifa_addr, !name.hasPrefix("lo") {
                if addr.pointee.sa_family == UInt8(AF_LINK), let data = ifa.ifa_data {
                    let stats = data.assumingMemoryBound(to: if_data.self).pointee
                    input += UInt64(stats.ifi_ibytes)
                    output += UInt64(stats.ifi_obytes)
                } else if addr.pointee.sa_family == UInt8(AF_INET), ipv4 == nil || name == "en0" {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        ipv4 = String(cString: host)
                    }
                }
            }
            cursor = ifa.ifa_next
        }

        let now = Date()
        if let last, input >= last.input, output >= last.output {
            let seconds = max(now.timeIntervalSince(last.date), 0.1)
            down = Double(input - last.input) / seconds
            up = Double(output - last.output) / seconds
            history = Array((history + [down]).suffix(40))
        }
        last = (input, output, now)
        address = ipv4 ?? "Geen verbinding"
    }

    override func compact(size: CGFloat) -> AnyView { AnyView(NetworkCompact(widget: self, size: size)) }
    override func card() -> AnyView? { AnyView(NetworkCard(widget: self)) }
}

private struct NetworkCompact: View {
    @ObservedObject var widget: NetworkWidget
    let size: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.06) {
            Label(Fmt.rate(widget.down), systemImage: "arrow.down")
            Label(Fmt.rate(widget.up), systemImage: "arrow.up")
        }
        .labelStyle(TightLabelStyle())
        .font(.system(size: size * 0.13, weight: .semibold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, size * 0.08)
    }
}

struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon.foregroundStyle(.secondary)
            configuration.title
        }
    }
}

private struct NetworkCard: View {
    @ObservedObject var widget: NetworkWidget

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Download").foregroundStyle(.secondary)
                    Text(Fmt.rate(widget.down)).font(.system(size: 18, weight: .semibold)).monospacedDigit()
                }
                VStack(alignment: .leading) {
                    Text("Upload").foregroundStyle(.secondary)
                    Text(Fmt.rate(widget.up)).font(.system(size: 18, weight: .semibold)).monospacedDigit()
                }
            }
            Sparkline(values: widget.history, tint: .green)
                .frame(height: 50)
            InfoRow(label: "IP-adres", value: widget.address)
            Button("Netwerkinstellingen") {
                NSWorkspaceBridge.open("x-apple.systempreferences:com.apple.Network-Settings.extension")
            }
            .buttonStyle(PillButtonStyle())
        }
        .font(.system(size: 12))
        .frame(width: 260, alignment: .leading)
    }
}

// MARK: Storage

final class StorageWidget: WidgetController {
    @Published var available: Int64 = 0
    @Published var total: Int64 = 0

    required init(id: UUID) {
        super.init(id: id)
        every(60) { [weak self] in self?.refresh() }
    }

    private func refresh() {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
        ])
        available = values?.volumeAvailableCapacityForImportantUsage ?? 0
        total = Int64(values?.volumeTotalCapacity ?? 0)
    }

    var usedFraction: Double { total > 0 ? 1 - Double(available) / Double(total) : 0 }

    override func compact(size: CGFloat) -> AnyView { AnyView(StorageCompact(widget: self, size: size)) }
    override func card() -> AnyView? { AnyView(StorageCard(widget: self)) }
}

private struct StorageCompact: View {
    @ObservedObject var widget: StorageWidget
    let size: CGFloat

    var body: some View {
        RingCompact(progress: widget.usedFraction,
                    text: ByteCountFormatter.string(fromByteCount: widget.available, countStyle: .file),
                    size: size, tint: widget.usedFraction > 0.9 ? .red : .blue)
    }
}

private struct StorageCard: View {
    @ObservedObject var widget: StorageWidget

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(Fmt.bytes(widget.available)) beschikbaar")
                .font(.system(size: 18, weight: .semibold))
            ProgressView(value: widget.usedFraction).tint(widget.usedFraction > 0.9 ? .red : .blue)
            InfoRow(label: "In gebruik", value: Fmt.bytes(widget.total - widget.available))
            InfoRow(label: "Totaal", value: Fmt.bytes(widget.total))
            Button("Opslagbeheer") {
                NSWorkspaceBridge.open("x-apple.systempreferences:com.apple.settings.Storage")
            }
            .buttonStyle(PillButtonStyle())
        }
        .font(.system(size: 12))
        .frame(width: 260, alignment: .leading)
    }
}

// MARK: Keep Awake

final class KeepAwakeWidget: WidgetController {
    @Published var active = false
    @Published var until: Date?
    private var assertion: IOPMAssertionID = 0

    required init(id: UUID) {
        super.init(id: id)
        every(5, fireNow: false) { [weak self] in
            guard let self, let until = self.until, until <= Date() else { return }
            self.stop()
        }
    }

    func start(minutes: Int?) {
        stop()
        let result = IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "GlassDock houdt je Mac wakker" as CFString, &assertion)
        guard result == kIOReturnSuccess else { return }
        active = true
        until = minutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) }
    }

    func stop() {
        if active { IOPMAssertionRelease(assertion) }
        active = false
        until = nil
    }

    override func tap() -> Bool {
        if active { stop() } else { start(minutes: nil) }
        showFlash(active ? "Wakker" : "Uit")
        return true
    }

    override func teardown() {
        stop()
        super.teardown()
    }

    override func compact(size: CGFloat) -> AnyView { AnyView(KeepAwakeCompact(widget: self, size: size)) }
    override func card() -> AnyView? { AnyView(KeepAwakeCard(widget: self)) }
}

private struct KeepAwakeCompact: View {
    @ObservedObject var widget: KeepAwakeWidget
    let size: CGFloat

    var body: some View {
        SymbolCompact(symbol: widget.active ? "cup.and.saucer.fill" : "cup.and.saucer", size: size,
                      tint: widget.active ? .orange : .primary, caption: widget.active ? "Aan" : "Uit")
    }
}

private struct KeepAwakeCard: View {
    @ObservedObject var widget: KeepAwakeWidget

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(statusText).font(.system(size: 13, weight: .semibold))
            HStack(spacing: 6) {
                Button("Altijd") { widget.start(minutes: nil) }.buttonStyle(PillButtonStyle(prominent: widget.active && widget.until == nil))
                Button("1 u") { widget.start(minutes: 60) }.buttonStyle(PillButtonStyle())
                Button("2 u") { widget.start(minutes: 120) }.buttonStyle(PillButtonStyle())
                Button("4 u") { widget.start(minutes: 240) }.buttonStyle(PillButtonStyle())
                Button("Uit") { widget.stop() }.buttonStyle(PillButtonStyle(prominent: !widget.active))
            }
        }
        .frame(width: 280, alignment: .leading)
    }

    private var statusText: String {
        guard widget.active else { return "Je Mac gaat normaal in sluimer." }
        if let until = widget.until { return "Wakker tot \(Fmt.hm.string(from: until))" }
        return "Je Mac blijft wakker."
    }
}

// MARK: Lock and Sleep

final class LockSleepWidget: WidgetController {
    override func compact(size: CGFloat) -> AnyView { AnyView(SymbolCompact(symbol: "lock", size: size)) }
    override func card() -> AnyView? { AnyView(LockSleepCard()) }
}

private struct LockSleepCard: View {
    var body: some View {
        HStack(spacing: 14) {
            action("Vergrendel", "lock.fill") {
                // Ctrl-Cmd-Q, the system shortcut. Needs Accessibility access for GlassDock.
                Script.run("tell application \"System Events\" to keystroke \"q\" using {command down, control down}")
            }
            action("Scherm uit", "display") { Shell.launch("/usr/bin/pmset", ["displaysleepnow"]) }
            action("Sluimer", "moon.zzz.fill") { Shell.launch("/usr/bin/pmset", ["sleepnow"]) }
        }
        .frame(width: 260)
    }

    private func action(_ title: String, _ symbol: String, _ perform: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button {
                CardPresenter.shared.close()
                perform()
            } label: {
                Image(systemName: symbol)
            }
            .buttonStyle(RoundIconButtonStyle(size: 46))
            Text(title).font(.system(size: 11))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: Appearance

final class AppearanceWidget: WidgetController {
    @Published var dark = false

    required init(id: UUID) {
        super.init(id: id)
        every(2) { [weak self] in
            let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            if self?.dark != dark { self?.dark = dark }
        }
    }

    func set(dark: Bool) {
        Script.run("tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)")
        self.dark = dark
    }

    override func tap() -> Bool {
        set(dark: !dark)
        return true
    }

    override func compact(size: CGFloat) -> AnyView { AnyView(AppearanceCompact(widget: self, size: size)) }
    override func card() -> AnyView? { AnyView(AppearanceCard(widget: self)) }
}

private struct AppearanceCompact: View {
    @ObservedObject var widget: AppearanceWidget
    let size: CGFloat

    var body: some View {
        SymbolCompact(symbol: widget.dark ? "moon.fill" : "sun.max.fill", size: size,
                      tint: widget.dark ? .indigo : .orange, caption: widget.dark ? "Donker" : "Licht")
    }
}

private struct AppearanceCard: View {
    @ObservedObject var widget: AppearanceWidget

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button("Licht") { widget.set(dark: false) }.buttonStyle(PillButtonStyle(prominent: !widget.dark))
                Button("Donker") { widget.set(dark: true) }.buttonStyle(PillButtonStyle(prominent: widget.dark))
            }
            Button("Weergave-instellingen") {
                NSWorkspaceBridge.open("x-apple.systempreferences:com.apple.Appearance-Settings.extension")
            }
            .buttonStyle(PillButtonStyle())
        }
        .frame(width: 220, alignment: .leading)
    }
}
