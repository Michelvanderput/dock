import AppKit

/// The geometry of the Dock, shared by the window (to size itself) and the view (for magnification).
enum DockLayout {
    static let pad: CGFloat = 8
    static let spacing: CGFloat = 6
    static let labelRoom: CGFloat = 36

    /// The config with the icon size shrunk so the Dock fits the screen, like the macOS Dock.
    @MainActor
    static func fitted(_ c: DockConfig, _ items: [DockItem]) -> DockConfig {
        guard let screen = NSScreen.screens.first, !items.isEmpty else { return c }
        let available = screen.frame.width - 16
        let full = barWidth(items, c)
        guard full > available else { return c }
        var zero = c
        zero.iconSize = 0
        let fixed = barWidth(items, zero)
        let perPoint = (full - fixed) / CGFloat(c.iconSize)
        guard perPoint > 0 else { return c }
        var fitted = c
        fitted.iconSize = Double(max(20, ((available - fixed) / perPoint).rounded(.down)))
        // Keep the same magnification ratio.
        fitted.magnifiedSize = max(fitted.iconSize, c.magnifiedSize * fitted.iconSize / c.iconSize)
        return fitted
    }

    static func barHeight(_ c: DockConfig) -> CGFloat {
        CGFloat(c.iconSize) + pad * 2
    }

    static func width(of item: DockItem, _ c: DockConfig) -> CGFloat {
        let s = CGFloat(c.iconSize)
        switch item {
        case .app, .folder, .trash, .stack:
            return s
        case .separator:
            return 9
        case .widget(let widget):
            let units = widget.kind.widthUnits
            return s * units + (units - 1) * spacing
        case .pager:
            return s * 0.5
        }
    }

    static func barWidth(_ items: [DockItem], _ c: DockConfig) -> CGFloat {
        let content = items.reduce(CGFloat(0)) { $0 + width(of: $1, c) }
        return content + spacing * CGFloat(max(0, items.count - 1)) + pad * 2
    }

    /// How much wider the row can get while icons are magnified.
    static func growth(_ c: DockConfig) -> CGFloat {
        c.magnification ? CGFloat(max(0, c.magnifiedSize - c.iconSize)) * 2.6 : 0
    }

    static func panelSize(_ items: [DockItem], _ c: DockConfig) -> CGSize {
        let tallest = c.magnification ? max(c.magnifiedSize, c.iconSize) : c.iconSize
        // Room for growth on both sides: near an end of the Dock all growth goes one way.
        // Whole points, so the window and the view agree on where items are.
        return CGSize(
            width: (barWidth(items, c) + growth(c) * 2 + 24).rounded(),
            height: (CGFloat(tallest) + pad * 2 + CGFloat(c.bottomOffset) + labelRoom).rounded()
        )
    }

    struct Placement {
        var x: CGFloat
        var width: CGFloat
        var height: CGFloat
        var scale: CGFloat
    }

    struct Arrangement {
        var items: [Placement]
        var barMinX: CGFloat
        var barWidth: CGFloat
        var hovered: Int?
    }

    /// Where every item goes. Scales follow a cosine bump around the pointer, measured on the
    /// unmagnified layout, and the row is shifted so the spot under the pointer stays put,
    /// like the macOS Dock. Without that shift the hovered icon slides out from under the pointer.
    static func arrange(_ items: [DockItem], _ c: DockConfig, mouseX: CGFloat?, containerWidth: CGFloat) -> Arrangement {
        let s = CGFloat(c.iconSize)
        let base = items.map { width(of: $0, c) }
        let total = barWidth(items, c)
        var baseX: [CGFloat] = []
        var x = (containerWidth - total) / 2 + pad
        for w in base {
            baseX.append(x)
            x += w + spacing
        }

        guard let mouseX, !items.isEmpty else {
            let placements = items.indices.map { Placement(x: baseX[$0], width: base[$0], height: s, scale: 1) }
            return Arrangement(items: placements, barMinX: (containerWidth - total) / 2, barWidth: total, hovered: nil)
        }

        let maxScale = c.magnification ? CGFloat(max(c.magnifiedSize, c.iconSize) / c.iconSize) : 1
        let range = s * 2.5
        var scales = Array(repeating: CGFloat(1), count: items.count)
        for i in items.indices where items[i].magnifies && maxScale > 1 {
            let t = min(abs(mouseX - (baseX[i] + base[i] / 2)) / range, 1)
            scales[i] = 1 + (maxScale - 1) * (cos(t * .pi) + 1) / 2
        }
        let widths = items.indices.map { items[$0].magnifies ? base[$0] * scales[$0] : base[$0] }

        // The pointer's spot in the unmagnified row: item k, fraction f of its width.
        let last = items.count - 1
        let pivot = min(max(mouseX, baseX[0]), baseX[last] + base[last])
        var k = last
        var f: CGFloat = 1
        for i in items.indices where pivot < baseX[i] + base[i] + spacing {
            k = i
            f = min(1, max(0, (pivot - baseX[i]) / base[i]))
            break
        }
        var before: CGFloat = 0
        for i in 0..<k { before += widths[i] + spacing }
        var cursorX = pivot - (before + f * widths[k])

        var placements: [Placement] = []
        var hovered: Int?
        for i in items.indices {
            let w = widths[i]
            placements.append(Placement(x: cursorX, width: w, height: items[i].magnifies ? s * scales[i] : s,
                                        scale: items[i].magnifies ? scales[i] : 1))
            if mouseX >= cursorX - spacing / 2 && mouseX <= cursorX + w + spacing / 2 { hovered = i }
            cursorX += w + spacing
        }
        let barMinX = placements[0].x - pad
        let barMaxX = placements[last].x + placements[last].width + pad
        return Arrangement(items: placements, barMinX: barMinX, barWidth: barMaxX - barMinX, hovered: hovered)
    }
}
