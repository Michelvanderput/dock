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

// 2. Clicking a widget opens its card (Finder is the active app, like in real use).
activateFinder()
let widgets = start.items.filter { $0.id.hasPrefix("widget:") }
if let widget = widgets.first {
    move(to: widget.center)
    wait(0.4)
    let current = readState()?.item(widget.id) ?? widget
    click(current.center)
    wait(0.8)
    let card = readState()?.card ?? ""
    let cardWindow = glassDockWindows().count > 1
    if card.isEmpty { fail("click widget \(widget.id): no card opened (cardWindow=\(cardWindow))") }
    else { log("ok   click widget \(widget.id): card \(card)") }
    screenshot("04-widget-click")
    key(53) // Esc
    wait(0.5)
    if let after = readState()?.card, !after.isEmpty { fail("Esc did not close card \(after)") } else { log("ok   Esc closes card") }
} else {
    fail("no widgets in dock")
}

// 3. Clicking an app that is not running launches it.
activateFinder()
if let app = start.items.first(where: { $0.id.hasPrefix("app:") && !$0.running && !$0.id.contains("Finder") }) {
    let path = String(app.id.dropFirst(4))
    move(to: app.center)
    wait(0.4)
    let current = readState()?.item(app.id) ?? app
    click(current.center)
    var launched = false
    for _ in 0..<20 {
        wait(0.5)
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL?.standardizedFileURL.path == path }) {
            launched = true
            break
        }
    }
    screenshot("05-app-click")
    if launched { log("ok   click app \(path) launched it") } else { fail("click app \(path): did not launch") }
} else {
    log("skip app click: no pinned app that is not running")
}

// 4. Clicking the Downloads folder opens its card.
activateFinder()
if let folder = start.items.first(where: { $0.id == "folder" }) {
    move(to: folder.center)
    wait(0.4)
    click(readState()?.item("folder")?.center ?? folder.center)
    wait(0.8)
    let card = readState()?.card ?? ""
    if card == "folder" { log("ok   click Downloads opens card") } else { fail("click Downloads: card=\(card)") }
    screenshot("06-folder-click")
    key(53)
    wait(0.4)
}

log(failures == 0 ? "ALL PASSED" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
