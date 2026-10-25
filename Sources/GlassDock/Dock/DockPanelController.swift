import AppKit
import SwiftUI
import Combine

extension NSWindow.Level {
    static let glassDock = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
    static let glassDockCard = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
}

final class DockPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .glassDock
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Reacts to the first click even though the window is never key.
class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Tracks the pointer itself, so magnification works while another app is active.
final class DockHostingView<Content: View>: FirstMouseHostingView<Content> {
    var onMouseMove: ((CGPoint?) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onMouseMove?(event.locationInWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onMouseMove?(event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseMove?(nil)
    }
}

@MainActor
final class DockPanelController {
    static let shared = DockPanelController()

    let panel = DockPanel()
    let model = DockModel()
    let hover = HoverState()
    private var bag = Set<AnyCancellable>()

    /// Height of the top of the glass bar above the bottom of the window.
    var barTop: CGFloat {
        let c = DockSettings.shared.config
        return CGFloat(c.bottomOffset) + DockLayout.barHeight(c)
    }

    private init() {
        let host = DockHostingView(rootView: DockRootView(model: model, settings: .shared, hover: hover))
        host.onMouseMove = { [weak self] point in self?.mouseMoved(point) }
        panel.contentView = host

        DockSettings.shared.$config.map { _ in () }
            .merge(with: model.$items.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.layout() }
            .store(in: &bag)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.layout() }
            .store(in: &bag)
    }

    func show() {
        layout()
        panel.orderFrontRegardless()
    }

    func toggleVisibility() {
        if panel.isVisible {
            CardPresenter.shared.close()
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    func layout() {
        guard let screen = NSScreen.screens.first else { return }
        let size = DockLayout.panelSize(model.items, DockSettings.shared.config)
        let frame = NSRect(x: (screen.frame.midX - size.width / 2).rounded(),
                           y: screen.frame.minY,
                           width: size.width.rounded(),
                           height: size.height.rounded())
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    private func mouseMoved(_ point: CGPoint?) {
        guard let point else {
            if hover.x != nil { hover.x = nil }
            return
        }
        let c = DockSettings.shared.config
        // Once magnified, keep magnifying while the pointer is over the enlarged icons.
        let grown = c.magnification ? CGFloat(max(0, c.magnifiedSize - c.iconSize)) : 0
        let limit = hover.x == nil ? barTop : barTop + grown
        let newValue: CGFloat? = point.y <= limit ? point.x : nil
        if hover.x != newValue { hover.x = newValue }
    }
}
