import AppKit
import SwiftUI

final class CardPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .glassDockCard
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
    }

    // Key, so text fields in cards (note, to-do, calculator) take typing without activating the app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows one card at a time above the Dock, and closes it when you click elsewhere.
@MainActor
final class CardPresenter {
    static let shared = CardPresenter()

    private var panel: CardPanel?
    private(set) var currentID: String?
    private var monitors: [Any] = []

    func toggle(item: WidgetItem, anchor: String? = nil) {
        toggle(id: item.id.uuidString, anchor: anchor ?? item.id.uuidString) { Self.card(for: item) }
    }

    func show(item: WidgetItem, anchor: String? = nil) {
        show(id: item.id.uuidString, anchor: anchor ?? item.id.uuidString, content: Self.card(for: item))
    }

    func toggle(id: String, anchor: String, content: () -> AnyView) {
        if currentID == id { close() } else { show(id: id, anchor: anchor, content: content()) }
    }

    static func card(for item: WidgetItem) -> AnyView {
        let controller = WidgetStore.shared.controller(for: item)
        let body = controller.card() ?? AnyView(
            Text("Deze widget heeft geen kaart.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        )
        return AnyView(CardChrome(title: item.kind.title, symbol: item.kind.symbol) { body })
    }

    func show(id: String, anchor: String, content: AnyView) {
        close()
        let panel = CardPanel()
        let host = FirstMouseHostingView(rootView: content)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        panel.setFrame(frame(anchor: anchor, size: size), display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
        self.panel = panel
        currentID = id
        installMonitors()
    }

    func close() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        panel?.orderOut(nil)
        panel = nil
        currentID = nil
    }

    private func frame(anchor: String, size: CGSize) -> NSRect {
        let dock = DockPanelController.shared
        let window = dock.panel
        let screen = window.screen ?? NSScreen.screens.first
        let anchorX = FrameRegistry.frames[anchor].map { window.frame.minX + $0.midX } ?? window.frame.midX
        var x = anchorX - size.width / 2
        if let bounds = screen?.frame {
            x = min(max(x, bounds.minX + 4), bounds.maxX - size.width - 4)
        }
        // CardChrome adds 14pt around the glass for its shadow.
        let y = window.frame.minY + dock.barTop - 6
        return NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    private func installMonitors() {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { _ in
            Task { @MainActor in CardPresenter.shared.close() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { event in
            MainActor.assumeIsolated {
                let presenter = CardPresenter.shared
                if event.type == .keyDown {
                    if event.keyCode == 53 { presenter.close(); return nil } // Esc
                    return event
                }
                // Clicks in the Dock decide for themselves (another widget swaps the card).
                if event.window !== presenter.panel && event.window !== DockPanelController.shared.panel {
                    presenter.close()
                }
                return event
            }
        }) {
            monitors.append(local)
        }
    }
}
