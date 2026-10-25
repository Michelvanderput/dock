import CoreGraphics
import Foundation

/// The geometry of the Dock, shared by the window (to size itself) and the view (for magnification).
enum DockLayout {
    static let pad: CGFloat = 8
    static let spacing: CGFloat = 6
    static let labelRoom: CGFloat = 36

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
        return CGSize(
            width: barWidth(items, c) + growth(c) + 24,
            height: CGFloat(tallest) + pad * 2 + CGFloat(c.bottomOffset) + labelRoom
        )
    }

    struct Hover {
        var scales: [CGFloat]
        var index: Int?
    }

    /// Scales follow a cosine bump around the pointer, measured on the unmagnified layout
    /// so the result never feeds back into itself.
    static func hover(_ items: [DockItem], _ c: DockConfig, mouseX: CGFloat?, containerWidth: CGFloat) -> Hover {
        var scales = Array(repeating: CGFloat(1), count: items.count)
        guard let mouseX else { return Hover(scales: scales, index: nil) }

        let maxScale = c.magnification ? CGFloat(max(c.magnifiedSize, c.iconSize) / c.iconSize) : 1
        let range = CGFloat(c.iconSize) * 2.5
        var x = (containerWidth - barWidth(items, c)) / 2 + pad
        var index: Int?

        for (i, item) in items.enumerated() {
            let w = width(of: item, c)
            if mouseX >= x - spacing / 2 && mouseX <= x + w + spacing / 2 { index = i }
            if item.magnifies && maxScale > 1 {
                let t = min(abs(mouseX - (x + w / 2)) / range, 1)
                scales[i] = 1 + (maxScale - 1) * (cos(t * .pi) + 1) / 2
            }
            x += w + spacing
        }
        return Hover(scales: scales, index: index)
    }
}
