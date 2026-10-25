import SwiftUI
import AppKit

/// Reads Spotify and Apple Music over AppleScript, only while they are running.
final class NowPlayingWidget: WidgetController {
    enum Player: String, CaseIterable {
        case spotify = "Spotify"
        case music = "Music"

        var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
        var title: String { self == .spotify ? "Spotify" : "Apple Music" }
        var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    }

    struct Track: Equatable {
        var player: Player
        var title: String
        var artist: String
        var playing: Bool
        var artwork: URL?
        var position: Double
        var duration: Double
        var fetchedAt: Date
    }

    @Published var track: Track?

    required init(id: UUID) {
        super.init(id: id)
        every(2) { [weak self] in self?.poll() }
    }

    func poll() {
        let tracks = Player.allCases.filter(\.isRunning).compactMap { self.read($0) }
        let next = tracks.first(where: \.playing) ?? tracks.first
        if next?.title != track?.title || next?.playing != track?.playing || next?.player != track?.player
            || abs((next?.position ?? 0) - (track.map { currentPosition($0) } ?? 0)) > 2 {
            track = next
        }
    }

    func currentPosition(_ track: Track) -> Double {
        guard track.playing else { return track.position }
        return min(track.duration, track.position + Date().timeIntervalSince(track.fetchedAt))
    }

    private func read(_ player: Player) -> Track? {
        let artwork = player == .spotify ? "(artwork url of t)" : "\"\""
        let durationExpr = player == .spotify ? "((duration of t) / 1000)" : "(duration of t)"
        let source = """
        tell application "\(player.rawValue)"
            try
                set s to "paused"
                if player state is playing then set s to "playing"
                set t to current track
                return s & "||" & (name of t) & "||" & (artist of t) & "||" & \(artwork) & "||" & ((player position) as text) & "||" & (\(durationExpr) as text)
            on error
                return ""
            end try
        end tell
        """
        guard let output = Script.run(source), !output.isEmpty else { return nil }
        let parts = output.components(separatedBy: "||")
        guard parts.count >= 6 else { return nil }
        func number(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        return Track(player: player, title: parts[1], artist: parts[2], playing: parts[0] == "playing",
                     artwork: URL(string: parts[3]), position: number(parts[4]), duration: number(parts[5]),
                     fetchedAt: Date())
    }

    func command(_ command: String) {
        guard let player = track?.player ?? Player.allCases.first(where: \.isRunning) else { return }
        Script.run("tell application \"\(player.rawValue)\" to \(command)")
        poll()
    }

    func seek(to seconds: Double) {
        guard let player = track?.player else { return }
        Script.run("tell application \"\(player.rawValue)\" to set player position to \(Int(seconds))")
        poll()
    }

    override func tap() -> Bool {
        guard track != nil || Player.allCases.contains(where: \.isRunning) else { return false }
        command("playpause")
        return true
    }

    override func compact(size: CGFloat) -> AnyView { AnyView(NowPlayingCompact(widget: self, size: size)) }
    override func card() -> AnyView? { AnyView(NowPlayingCard(widget: self)) }
}

private struct Artwork: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(LinearGradient(colors: [.pink.opacity(0.8), .purple.opacity(0.8)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "music.note")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
    }
}

private struct NowPlayingCompact: View {
    @ObservedObject var widget: NowPlayingWidget
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.14) {
            Artwork(url: widget.track?.artwork, size: size * 0.7)
            VStack(alignment: .leading, spacing: size * 0.03) {
                Text(widget.track?.title ?? "Niets speelt")
                    .font(.system(size: size * 0.18, weight: .semibold))
                Text(widget.track?.artist ?? "Klik voor muziek")
                    .font(.system(size: size * 0.15))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if let track = widget.track {
                Image(systemName: track.playing ? "waveform" : "pause.fill")
                    .font(.system(size: size * 0.2, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.variableColor.iterative, isActive: track.playing)
            }
        }
        .padding(.horizontal, size * 0.15)
    }
}

private struct NowPlayingCard: View {
    @ObservedObject var widget: NowPlayingWidget

    var body: some View {
        VStack(spacing: 14) {
            if let track = widget.track {
                HStack(spacing: 14) {
                    Artwork(url: track.artwork, size: 96)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                        Text(track.artist).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                        Text(track.player.title).font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let position = widget.currentPosition(track)
                    VStack(spacing: 4) {
                        ProgressView(value: track.duration > 0 ? min(position / track.duration, 1) : 0)
                            .progressViewStyle(.linear)
                        HStack {
                            Text(Fmt.clock(position))
                            Spacer()
                            Text("-" + Fmt.clock(max(0, track.duration - position)))
                        }
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 18) {
                    Button { widget.command("previous track") } label: { Image(systemName: "backward.fill") }
                        .buttonStyle(RoundIconButtonStyle(size: 38))
                    Button { widget.command("playpause") } label: {
                        Image(systemName: track.playing ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(RoundIconButtonStyle(size: 48))
                    Button { widget.command("next track") } label: { Image(systemName: "forward.fill") }
                        .buttonStyle(RoundIconButtonStyle(size: 38))
                }
            } else {
                Text("Er speelt niets. Start Spotify of Apple Music.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                HStack {
                    if NSWorkspaceBridge.url(forBundleID: NowPlayingWidget.Player.spotify.bundleID) != nil {
                        Button("Open Spotify") { NSWorkspaceBridge.openApp(bundleID: NowPlayingWidget.Player.spotify.bundleID) }
                            .buttonStyle(PillButtonStyle(prominent: true))
                    }
                    Button("Open Muziek") { NSWorkspaceBridge.openApp(bundleID: NowPlayingWidget.Player.music.bundleID) }
                        .buttonStyle(PillButtonStyle())
                }
            }
        }
        .frame(width: 300)
    }
}
