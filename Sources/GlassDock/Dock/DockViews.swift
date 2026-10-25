import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DockRootView: View {
    @ObservedObject var model: DockModel
    @ObservedObject var settings: DockSettings
    @ObservedObject var hover: HoverState

    var body: some View {
        let config = settings.config
        let items = model.items
        let size = DockLayout.panelSize(items, config)
        let layout = DockLayout.arrange(items, config, mouseX: hover.x, containerWidth: size.width)
        let barHeight = DockLayout.barHeight(config)
        let bottom = size.height - CGFloat(config.bottomOffset)

        // Items are placed with .position (a layout change, unlike .offset), so hit areas and
        // the frames cards anchor to match what you see.
        ZStack(alignment: .topLeading) {
            GlassBackground(cornerRadius: CGFloat(config.iconSize) * 0.34 + DockLayout.pad)
                .frame(width: layout.barWidth, height: barHeight)
                .contextMenu { DockContextMenu() }
                .position(x: layout.barMinX + layout.barWidth / 2, y: bottom - barHeight / 2)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let place = index < layout.items.count
                    ? layout.items[index]
                    : DockLayout.Placement(x: 0, width: 0, height: 0, scale: 1)
                DockItemView(item: item, scale: place.scale, showLabel: layout.hovered == index,
                             config: config, model: model)
                    .frame(width: place.width, height: place.height, alignment: .bottom)
                    .background(FrameReporter(id: item.id))
                    .position(x: place.x + place.width / 2, y: bottom - DockLayout.pad - place.height / 2)
            }
        }
        .frame(width: size.width, height: size.height)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            model.handleDrop(providers)
        }
        // Follow the pointer instantly; only ease in and out when it enters or leaves.
        .animation(.easeOut(duration: 0.18), value: hover.x == nil)
    }
}

struct DockContextMenu: View {
    var body: some View {
        AddWidgetMenu()
        Divider()
        Button("Dock-instellingen…") { SettingsWindowController.shared.show() }
        Button("Stop GlassDock") { NSApp.terminate(nil) }
    }
}

struct AddWidgetMenu: View {
    var body: some View {
        Menu("Widget toevoegen") {
            ForEach(WidgetCategory.allCases) { category in
                Section(category.title) {
                    ForEach(WidgetKind.allCases.filter { $0.category == category }) { kind in
                        Button {
                            DockSettings.shared.addWidget(kind)
                        } label: {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                }
            }
        }
    }
}

struct DockLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(GlassBackground(cornerRadius: 9))
            .fixedSize()
    }
}

struct DockItemView: View {
    let item: DockItem
    let scale: CGFloat
    let showLabel: Bool
    let config: DockConfig
    @ObservedObject var model: DockModel

    var body: some View {
        content
            .overlay(alignment: .top) {
                if showLabel, let label = item.label {
                    DockLabel(text: label)
                        .offset(y: -32)
                        .allowsHitTesting(false)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        let s = CGFloat(config.iconSize)
        switch item {
        case .app(let app):
            AppIconView(app: app, size: s * scale, config: config, model: model)
        case .separator:
            Capsule()
                .fill(Color.primary.opacity(0.22))
                .frame(width: 1, height: s * 0.62)
                .frame(width: DockLayout.width(of: item, config), height: s)
        case .widget(let widget):
            WidgetCell(item: widget, size: s)
        case .stack(let widgets):
            StackItemView(widgets: widgets, size: s * scale)
        case .pager(let page, let count):
            PagerItemView(page: page, count: count, size: s) { model.nextPage() }
        case .folder:
            FolderItemView(folder: model.downloads, size: s * scale)
        case .trash:
            TrashItemView(size: s * scale)
        }
    }
}

struct AppIconView: View {
    let app: DockApp
    let size: CGFloat
    let config: DockConfig
    @ObservedObject var model: DockModel

    var body: some View {
        let bouncing = model.launching.contains(app.path)
        Image(nsImage: IconCache.icon(for: app.path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .offset(y: bouncing ? -size * 0.28 : 0)
            .animation(bouncing ? .easeInOut(duration: 0.3).repeatForever(autoreverses: true) : .easeOut(duration: 0.2),
                       value: bouncing)
            .overlay(alignment: .bottom) {
                if config.showIndicators && app.isRunning {
                    Circle()
                        .fill(Color.primary.opacity(0.75))
                        .frame(width: 4, height: 4)
                        .offset(y: DockLayout.pad - 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.open(app) }
            .contextMenu {
                Button(app.isRunning ? "Toon" : "Open") { model.open(app) }
                Button("Toon in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
                Divider()
                Button(app.isPinned ? "Verwijder uit Dock" : "Houd in Dock") { model.togglePin(app) }
                if app.isRunning {
                    Divider()
                    Button("Verberg") { model.hide(app) }
                    Button("Stop") { model.quit(app) }
                }
            }
    }
}

struct PagerItemView: View {
    let page: Int
    let count: Int
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: size * 0.26, weight: .semibold))
            HStack(spacing: 2) {
                ForEach(0..<count, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Color.primary : Color.primary.opacity(0.3))
                        .frame(width: 3.5, height: 3.5)
                }
            }
            .fixedSize()
        }
        .frame(width: size * 0.5, height: size)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

struct StackItemView: View {
    let widgets: [WidgetItem]
    let size: CGFloat

    var body: some View {
        WidgetTile(width: size, height: size) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: size * 0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("\(widgets.count)")
                    .font(.system(size: size * 0.17, weight: .bold))
                    .padding(.horizontal, size * 0.08)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
                    .padding(size * 0.08)
            }
        }
        .background(FrameReporter(id: "stack"))
        .contentShape(Rectangle())
        .onTapGesture {
            CardPresenter.shared.toggle(id: "stack", anchor: "stack") {
                AnyView(CardChrome(title: "Meer widgets", symbol: "square.stack.3d.up") {
                    StackCard(widgets: widgets)
                })
            }
        }
    }
}

struct StackCard: View {
    let widgets: [WidgetItem]

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 64), spacing: 10, alignment: .leading)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(widgets) { widget in
                WidgetCell(item: widget, size: 64, anchor: "stack")
            }
        }
        .frame(width: 4 * 64 + 3 * 10, alignment: .leading)
    }
}

struct FrameReporter: View {
    let id: String

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { FrameRegistry.frames[id] = geo.frame(in: .global) }
                .onChange(of: geo.frame(in: .global)) { _, frame in FrameRegistry.frames[id] = frame }
        }
    }
}

// MARK: Trash

struct TrashItemView: View {
    let size: CGFloat
    @State private var isFull = TrashItemView.trashHasItems()
    @State private var targeted = false
    private static let refresh = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        let name = isFull ? NSImage.trashFullName : NSImage.trashEmptyName
        Image(nsImage: NSImage(named: name) ?? NSImage())
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .scaleEffect(targeted ? 1.1 : 1)
            .animation(.easeOut(duration: 0.15), value: targeted)
            .contentShape(Rectangle())
            .onTapGesture {
                CardPresenter.shared.close()
                NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash"))
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                        guard let url = (object as? NSURL)?.absoluteURL else { return }
                        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    }
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    isFull = TrashItemView.trashHasItems()
                }
                return true
            }
            .onReceive(Self.refresh) { _ in isFull = TrashItemView.trashHasItems() }
            .contextMenu {
                Button("Open") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash"))
                }
                Button("Leeg prullenmand") {
                    Script.run("tell application \"Finder\" to empty trash")
                    isFull = TrashItemView.trashHasItems()
                }
            }
    }

    static func trashHasItems() -> Bool {
        let path = NSHomeDirectory() + "/.Trash"
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return contents.contains { $0 != ".DS_Store" }
    }
}
