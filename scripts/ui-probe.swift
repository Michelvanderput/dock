// Drives a running GlassDock (started with GLASSDOCK_DEBUG=1) with real mouse events and
// reports whether hovering and clicking work. Used in CI; run it yourself with:
//   GLASSDOCK_DEBUG=1 build/GlassDock.app/Contents/MacOS/GlassDock &
//   swiftc scripts/ui-probe.swift -o build/ui-probe && build/ui-probe
import AppKit
import CoreGraphics

var failures = 0
func log(_ s: String) { print("PROBE: " + s); fflush(stdout) }
func fail(_ s: String) { failures += 1; log("FAIL " + s) }
func wait(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

struct Item {
    let id: String
    let rect: CGRect
    let running: Bool
    var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
}

struct State {
    let items: [Item]
    let hoverX: Double
    let card: String
    let panel: CGRect
    func item(_ id: String) -> Item? { items.first { $0.id == id } }
}

func readState() -> State? {
    guard let data = FileManager.default.contents(atPath: "/tmp/glassdock-debug.json"),
          let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
    let items = (json["items"] as? [[String: Any]] ?? []).map {
        Item(id: $0["id"] as? String ?? "",
             rect: CGRect(x: $0["x"] as? Double ?? 0, y: $0["y"] as? Double ?? 0,
                          width: $0["w"] as? Double ?? 0, height: $0["h"] as? Double ?? 0),
             running: $0["running"] as? Bool ?? false)
    }
    let p = json["panel"] as? [String: Double] ?? [:]
    return State(items: items, hoverX: json["hoverX"] as? Double ?? -1, card: json["card"] as? String ?? "",
                 panel: CGRect(x: p["x"] ?? 0, y: p["y"] ?? 0, width: p["w"] ?? 0, height: p["h"] ?? 0))
}

var cursor = CGPoint(x: 400, y: 300)
func post(_ type: CGEventType, _ point: CGPoint, _ button: CGMouseButton = .left) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)?
        .post(tap: .cghidEventTap)
}
func move(to target: CGPoint, steps: Int = 12) {
    for i in 1...steps {
        let t = CGFloat(i) / CGFloat(steps)
        post(.mouseMoved, CGPoint(x: cursor.x + (target.x - cursor.x) * t, y: cursor.y + (target.y - cursor.y) * t))
        wait(0.015)
    }
    cursor = target
}
func click(_ point: CGPoint, right: Bool = false) {
    move(to: point)
    wait(0.2)
    post(right ? .rightMouseDown : .leftMouseDown, point, right ? .right : .left)
    wait(0.08)
    post(right ? .rightMouseUp : .leftMouseUp, point, right ? .right : .left)
}
func key(_ code: CGKeyCode) {
    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
}
func screenshot(_ name: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "shots/\(name).png"]
    try? p.run()
    p.waitUntilExit()
}
func glassDockWindows() -> [(layer: Int, bounds: CGRect)] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { w in
        guard w[kCGWindowOwnerName as String] as? String == "GlassDock",
              let b = w[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: b) else { return nil }
        return (w[kCGWindowLayer as String] as? Int ?? 0, rect)
    }
}
func activateFinder() {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
    wait(0.8)
}

// MARK: Run

log("post events allowed: \(CGPreflightPostEventAccess()), screen capture allowed: \(CGPreflightScreenCaptureAccess())")
if let screen = NSScreen.screens.first { log("screen \(screen.frame)") }

var state: State?
for _ in 0..<60 {
    state = readState()
    if let s = state, !s.items.isEmpty { break }
    wait(0.5)
}
guard let start = state, !start.items.isEmpty else {
    fail("no debug state from GlassDock")
    exit(1)
}
log("panel \(start.panel)")
for item in start.items { log("item \(item.id) \(item.rect) running=\(item.running)") }
for w in glassDockWindows() { log("window layer=\(w.layer) bounds=\(w.bounds)") }

activateFinder()
move(to: CGPoint(x: start.panel.midX, y: start.panel.minY - 150))
wait(0.5)
screenshot("01-start")

// 1. Hover: the item under the pointer must stay under the pointer while magnified.
let hoverTargets = start.items.filter { !$0.id.hasPrefix("sep:") }
for (index, target) in hoverTargets.enumerated() {
    move(to: target.center)
    wait(0.45)
    guard let now = readState(), let moved = now.item(target.id) else { fail("hover \(target.id): no state"); continue }
    let inside = moved.rect.minX <= cursor.x && cursor.x <= moved.rect.maxX
    let drift = Int((moved.rect.midX - cursor.x).rounded())
    let tracked = abs(now.hoverX - Double(cursor.x)) < 1.5
    let line = "hover \(target.id): cursor=\(Int(cursor.x)) item=\(Int(moved.rect.minX))...\(Int(moved.rect.maxX)) drift=\(drift) hoverX=\(Int(now.hoverX))"
    if inside && tracked { log("ok   " + line) } else { fail(line) }
    if index == 0 { screenshot("02-hover-first") }
    if index == hoverTargets.count / 2 { screenshot("03-hover-middle") }
}
move(to: CGPoint(x: start.panel.midX, y: start.panel.minY - 150))
wait(0.5)

let screenBounds = NSScreen.screens.first?.frame ?? .zero
func onScreen(_ item: Item) -> Bool { item.rect.minX >= screenBounds.minX && item.rect.maxX <= screenBounds.maxX }
let bar = start.items.filter { !$0.id.hasPrefix("sep:") }
let offScreen = bar.filter { !onScreen($0) }
if offScreen.isEmpty { log("ok   whole Dock fits on screen") } else { fail("\(offScreen.count) items off screen: \(offScreen.map(\.id))") }

func appLog() -> String { (try? String(contentsOfFile: "shots/app.log", encoding: .utf8)) ?? "" }
func count(_ needle: String) -> Int { appLog().components(separatedBy: needle).count - 1 }

/// Hover first, so the click lands where the magnified item really is.
func clickItem(_ id: String, right: Bool = false) {
    guard let item = readState()?.item(id) ?? start.item(id) else { return }
    move(to: item.center)
    wait(0.4)
    click(readState()?.item(id)?.center ?? item.center, right: right)
}

// 2. Every widget reacts to a click, with Finder as the active app like in real use.
for widget in bar.filter({ $0.id.hasPrefix("widget:") && onScreen($0) }) {
    activateFinder()
    let taps = count("tap widget")
    clickItem(widget.id)
    wait(0.7)
    if count("tap widget") > taps { log("ok   click \(widget.id) reached the widget") } else { fail("click \(widget.id) did nothing") }
    key(53)
    wait(0.3)
}

// 3. A widget without a quick action opens its card; Esc closes it.
activateFinder()
if let clock = bar.first(where: { $0.id.hasPrefix("widget:") && onScreen($0) }) {
    clickItem(clock.id)
    wait(0.7)
    let card = readState()?.card ?? ""
    if card.isEmpty { fail("first widget: no card") } else { log("ok   first widget opens card") }
    screenshot("04-widget-card")
    key(53)
    wait(0.4)
    if let after = readState()?.card, !after.isEmpty { fail("Esc did not close card") } else { log("ok   Esc closes card") }
}

// 4. Clicking apps launches them, twice in a row with another app in front.
var launchedCount = 0
for app in bar.filter({ $0.id.hasPrefix("app:") && !$0.running && onScreen($0) && !$0.id.contains("Launchpad") }).prefix(2) {
    activateFinder()
    let path = String(app.id.dropFirst(4))
    clickItem(app.id)
    var launched = false
    for _ in 0..<20 {
        wait(0.5)
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL?.standardizedFileURL.path == path }) {
            launched = true
            break
        }
    }
    if launched { launchedCount += 1; log("ok   click app \(path) launched it") } else { fail("click app \(path): did not launch") }
}
screenshot("05-apps-launched")
if launchedCount == 0 { fail("no app could be launched from the Dock") }

// 5. Downloads opens its card.
activateFinder()
if bar.contains(where: { $0.id == "folder" && onScreen($0) }) {
    clickItem("folder")
    wait(0.8)
    let card = readState()?.card ?? ""
    if card == "folder" { log("ok   click Downloads opens card") } else { fail("click Downloads: card=\(card)") }
    screenshot("06-folder-card")
    key(53)
    wait(0.4)
}

// 6. Right-click shows a menu.
activateFinder()
if let finder = bar.first(where: { $0.id.contains("Finder.app") && onScreen($0) }) {
    let before = glassDockWindows().count
    clickItem(finder.id, right: true)
    wait(0.8)
    let menus = glassDockWindows().filter { $0.layer >= 100 }
    screenshot("07-context-menu")
    if !menus.isEmpty || glassDockWindows().count > before { log("ok   right-click shows a menu") } else { fail("right-click: no menu") }
    key(53)
    wait(0.4)
}

log(failures == 0 ? "ALL PASSED" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
