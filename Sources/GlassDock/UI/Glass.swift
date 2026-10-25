import SwiftUI
import AppKit

/// Liquid Glass on macOS 26, frosted glass on macOS 14 and 15.
struct GlassBackground: View {
    var cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: shape)
        } else {
            FrostedGlass(shape: shape)
        }
        #else
        FrostedGlass(shape: shape)
        #endif
    }
}

private struct FrostedGlass: View {
    let shape: RoundedRectangle

    var body: some View {
        VisualEffect(material: .popover)
            .overlay(
                LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.02)],
                               startPoint: .top, endPoint: .bottom)
            )
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.08)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.8
                )
            )
            .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        // Stay frosted even though GlassDock is never the active app.
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// The rounded tile a widget sits on inside the Dock.
struct WidgetTile<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: height * 0.26, style: .continuous)
        content
            .frame(width: width, height: height)
            .background(shape.fill(Color.primary.opacity(0.07)))
            .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            .clipShape(shape)
    }
}

/// The frame every card gets: glass, a small header and padding for the shadow.
struct CardChrome<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .background(GlassBackground(cornerRadius: 22))
        .padding(14)
    }
}

struct PillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(
                Capsule().fill(prominent ? Color.accentColor : Color.primary.opacity(configuration.isPressed ? 0.2 : 0.1))
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

struct RoundIconButtonStyle: ButtonStyle {
    var size: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.42, weight: .semibold))
            .frame(width: size, height: size)
            .background(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.22 : 0.1)))
            .contentShape(Circle())
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 12))
    }
}

struct Sparkline: View {
    let values: [Double]
    var maxValue: Double? = nil
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            let top = max(maxValue ?? (values.max() ?? 1), 0.0001)
            let step = values.count > 1 ? geo.size.width / CGFloat(values.count - 1) : 0
            let points = values.enumerated().map { i, v in
                CGPoint(x: CGFloat(i) * step, y: geo.size.height * (1 - CGFloat(min(v / top, 1))))
            }
            ZStack {
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: CGPoint(x: first.x, y: geo.size.height))
                    for pt in points { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: points.last?.x ?? 0, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(tint.opacity(0.18))
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: first)
                    for pt in points.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
    }
}

/// A symbol with an optional caption, the default look of a compact widget.
struct SymbolCompact: View {
    let symbol: String
    let size: CGFloat
    var tint: Color = .primary
    var caption: String? = nil

    var body: some View {
        VStack(spacing: size * 0.05) {
            Image(systemName: symbol)
                .font(.system(size: size * (caption == nil ? 0.42 : 0.34), weight: .medium))
                .foregroundStyle(tint)
            if let caption {
                Text(caption)
                    .font(.system(size: size * 0.16, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(size * 0.06)
    }
}

struct RingCompact: View {
    let progress: Double
    let text: String
    let size: CGFloat
    var tint: Color = .accentColor

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.15), lineWidth: size * 0.07)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(text)
                .font(.system(size: size * 0.18, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, size * 0.1)
        }
        .padding(size * 0.12)
    }
}
