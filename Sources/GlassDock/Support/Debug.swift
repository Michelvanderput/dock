import AppKit
import Combine

/// With GLASSDOCK_DEBUG=1 the app logs clicks to stderr and writes the Dock's item frames
/// to /tmp/glassdock-debug.json, so scripts/ui-probe.swift can test it on a real Mac.
@MainActor
enum Debug {
    static let enabled = ProcessInfo.processInfo.environment["GLASSDOCK_DEBUG"] == "1"
    private static var timer: AnyCancellable?

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data(("GLASSDOCK: " + message() + "\n").utf8))
    }

    static func start() {
        guard enabled else { return }
        timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
            .sink { _ in dump() }
    }

    private static func dump() {
        let controller = DockPanelController.shared
        let window = controller.panel.frame
        guard let screenHeight = NSScreen.screens.first?.frame.height else { return }
        var items: [[String: Any]] = []
        for item in controller.model.items {
            guard let frame = FrameRegistry.frames[item.id] else { continue }
            var entry: [String: Any] = [
                "id": item.id,
                // Screen coordinates with a top-left origin, like CGEvent uses.
                "x": window.minX + frame.minX,
                "y": screenHeight - window.maxY + frame.minY,
                "w": frame.width,
                "h": frame.height,
            ]
            if case .app(let app) = item { entry["running"] = app.isRunning }
            items.append(entry)
        }
        let state: [String: Any] = [
            "panel": ["x": window.minX, "y": screenHeight - window.maxY, "w": window.width, "h": window.height],
            "hoverX": controller.hover.x.map { window.minX + $0 } ?? -1,
            "card": CardPresenter.shared.currentID ?? "",
            "items": items,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/glassdock-debug.json"), options: .atomic)
        }
    }
}
