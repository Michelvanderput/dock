import AppKit
import SwiftUI
import Combine

extension NSWindow.Level {
    // One above the system Dock: its hidden window still lies along the bottom edge on macOS 26.
    static let glassDock = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
    static let glassDockCard = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 2)
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
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?
    var onRightMouseDown: ((NSEvent, NSView) -> Void)?
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

    // Left clicks are handled here, from the same layout the view draws, instead of by SwiftUI
    // tap gestures: those sometimes dropped a click while the Dock was re-rendering
    // (an app bouncing, the app list changing). Control-click still goes to the context menu.
    override func mouseDown(with event: NSEvent) {
        Debug.log("mouseDown at \(event.locationInWindow) windowKey=\(window?.isKeyWindow ?? false)")
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
        } else {
            onMouseDown?(event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !event.modifierFlags.contains(.control) {
            onMouseUp?(event)
        }
    }

    override func mouseDragged(with event: NSEvent) {}

    override func rightMouseDown(with event: NSEvent) {
        Debug.log("rightMouseDown at \(event.locationInWindow)")
        onRightMouseDown?(event, self)
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
    private var pressed: (id: String, time: TimeInterval)?
    private var longPress: Task<Void, Never>?
    private var pointerPoll: AnyCancellable?

    /// The settings, with the icon size shrunk to fit the screen.
    var config: DockConfig { DockLayout.fitted(DockSettings.shared.config, model.items) }

    /// Height of the top of the glass bar above the bottom of the window.
    var barTop: CGFloat {
        let c = config
        return CGFloat(c.bottomOffset) + DockLayout.barHeight(c)
    }

    private init() {
        let host = DockHostingView(rootView: DockRootView(model: model, settings: .shared, hover: hover))
        host.onMouseMove = { [weak self] point in self?.mouseMoved(point) }
        host.onMouseDown = { [weak self] event in self?.mouseDown(event) }
        host.onMouseUp = { [weak self] event in self?.mouseUp(event) }
        host.onRightMouseDown = { [weak self] event, view in self?.rightMouseDown(event, in: view) }
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
        let size = DockLayout.panelSize(model.items, config)
        let frame = NSRect(x: (screen.frame.midX - size.width / 2).rounded(),
                           y: screen.frame.minY,
                           width: size.width.rounded(),
                           height: size.height.rounded())
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    /// The Dock item at a point in window coordinates, using the layout the view draws.
    /// The strip below an icon counts too, so you can fling the pointer to the bottom edge.
    func item(at point: CGPoint) -> DockItem? {
        let c = config
        let items = model.items
        let size = DockLayout.panelSize(items, c)
        let layout = DockLayout.arrange(items, c, mouseX: hover.x ?? point.x, containerWidth: size.width)
        // The view is centred in the window if their widths differ.
        let x = point.x - (panel.frame.width - size.width) / 2
        for (index, place) in layout.items.enumerated() where index < items.count {
            let top = CGFloat(c.bottomOffset) + DockLayout.pad + place.height
            guard point.y <= top,
                  x >= place.x - DockLayout.spacing / 2,
                  x <= place.x + place.width + DockLayout.spacing / 2 else { continue }
            if case .separator = items[index] { return nil }
            return items[index]
        }
        return nil
    }

    private func mouseDown(_ event: NSEvent) {
        longPress?.cancel()
        guard let item = item(at: event.locationInWindow) else {
            pressed = nil
            return
        }
        pressed = (item.id, event.timestamp)
        // Press and hold opens a widget's card while you hold.
        longPress = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled, self.pressed?.id == item.id else { return }
            self.pressed = nil
            self.model.longPress(item)
        }
    }

    private func mouseUp(_ event: NSEvent) {
        longPress?.cancel()
        guard let press = pressed else { return }
        pressed = nil
        guard let item = item(at: event.locationInWindow), item.id == press.id else { return }
        // macOS 26 can hand over mouseDown only at release, so judge the hold by the event times.
        if event.timestamp - press.time >= 0.35 {
            model.longPress(item)
        } else {
            model.click(item)
        }
    }

    private func rightMouseDown(_ event: NSEvent, in view: NSView) {
        longPress?.cancel()
        pressed = nil
        CardPresenter.shared.close()
        let menu = DockMenus.menu(for: item(at: event.locationInWindow), model: model)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func mouseMoved(_ point: CGPoint?) {
        guard let point else {
            if hover.x != nil { hover.x = nil }
            pollPointer(false)
            return
        }
        let c = config
        // Once magnified, keep magnifying while the pointer is over the enlarged icons.
        let grown = c.magnification ? CGFloat(max(0, c.magnifiedSize - c.iconSize)) : 0
        let limit = hover.x == nil ? barTop : barTop + grown
        let newValue: CGFloat? = point.y <= limit ? point.x : nil
        if hover.x != newValue { hover.x = newValue }
        pollPointer(newValue != nil)
    }

    /// While the pointer is over the Dock, also read its real position every frame: macOS 26
    /// sometimes drops the last mouse-moved event, which left magnification beside the pointer.
    private func pollPointer(_ active: Bool) {
        guard active != (pointerPoll != nil) else { return }
        guard active else {
            pointerPoll = nil
            return
        }
        pointerPoll = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let mouse = NSEvent.mouseLocation
                let frame = self.panel.frame
                let point = CGPoint(x: mouse.x - frame.minX, y: mouse.y - frame.minY)
                self.mouseMoved(frame.contains(mouse) ? point : nil)
            }
    }
}
