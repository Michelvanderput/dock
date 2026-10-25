import AppKit
import SwiftUI
import Combine

struct FileEntry: Identifiable, Hashable {
    let url: URL
    let name: String
    let date: Date
    let size: Int64
    let inProgress: Bool
    var id: URL { url }
}

/// Watches a folder (Downloads) and lists its contents newest first.
@MainActor
final class FolderModel: ObservableObject {
    let url: URL
    @Published private(set) var entries: [FileEntry] = []
    /// Bumped when a download finishes, so the icon can hop.
    @Published private(set) var hop = 0

    private var source: DispatchSourceFileSystemObject?
    private var bag = Set<AnyCancellable>()

    init(url: URL) {
        self.url = url
        reload()
        watch()
        // Downloads in progress grow without touching the folder itself.
        Timer.publish(every: 2, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self, self.entries.contains(where: \.inProgress) else { return }
                self.reload()
            }
            .store(in: &bag)
    }

    var isDownloading: Bool { entries.contains(where: \.inProgress) }

    func reload() {
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey, .fileSizeKey, .totalFileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys,
                                                                 options: [.skipsHiddenFiles])) ?? []
        let fresh = urls.map { item -> FileEntry in
            let values = try? item.resourceValues(forKeys: Set(keys))
            let ext = item.pathExtension.lowercased()
            return FileEntry(
                url: item,
                name: item.lastPathComponent,
                date: values?.addedToDirectoryDate ?? values?.contentModificationDate ?? .distantPast,
                size: Int64(values?.totalFileSize ?? values?.fileSize ?? 0),
                inProgress: ["download", "crdownload", "part", "partial"].contains(ext)
            )
        }
        .sorted { $0.date > $1.date }

        let finishedBefore = Set(entries.filter { !$0.inProgress }.map(\.url))
        if !entries.isEmpty, fresh.contains(where: { !$0.inProgress && !finishedBefore.contains($0.url) }) {
            hop += 1
        }
        entries = fresh
    }

    private func watch() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }
}

struct FolderItemView: View {
    @ObservedObject var folder: FolderModel
    let size: CGFloat
    @State private var hopOffset: CGFloat = 0

    var body: some View {
        let top = Array(folder.entries.prefix(3))
        ZStack {
            if top.isEmpty {
                Image(nsImage: IconCache.icon(for: folder.url.path))
                    .resizable()
                    .interpolation(.high)
            } else {
                ForEach(Array(top.enumerated().reversed()), id: \.element.id) { index, entry in
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size * 0.82, height: size * 0.82)
                        .rotationEffect(.degrees(Double(index) * -7))
                        .offset(x: CGFloat(index) * -size * 0.04, y: CGFloat(index) * -size * 0.03)
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                }
            }
            if folder.isDownloading {
                ProgressView()
                    .controlSize(.small)
                    .padding(4)
                    .background(Circle().fill(.regularMaterial))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(width: size, height: size)
        .offset(y: hopOffset)
        .background(FrameReporter(id: "folder"))
        .onChange(of: folder.hop) { _, _ in
            withAnimation(.easeOut(duration: 0.18)) { hopOffset = -size * 0.35 }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                withAnimation(.interpolatingSpring(stiffness: 320, damping: 9)) { hopOffset = 0 }
            }
        }
    }
}

struct FolderCard: View {
    @ObservedObject var folder: FolderModel
    @State private var query = ""

    private struct Group: Identifiable {
        let title: String
        let entries: [FileEntry]
        var id: String { title }
    }

    private var groups: [Group] {
        let calendar = Calendar.current
        let filtered = folder.entries
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .prefix(200)
        var result: [Group] = []
        for entry in filtered {
            let title: String
            if calendar.isDateInToday(entry.date) { title = "Vandaag" }
            else if calendar.isDateInYesterday(entry.date) { title = "Gisteren" }
            else { title = Fmt.sentence(Fmt.dayLong.string(from: entry.date)) }
            if let last = result.last, last.title == title {
                result[result.count - 1] = Group(title: title, entries: last.entries + [entry])
            } else {
                result.append(Group(title: title, entries: [entry]))
            }
        }
        return result
    }

    private var freeSpace: String {
        let values = try? folder.url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Fmt.bytes(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Zoeken", text: $query)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(groups) { group in
                        Text(group.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        ForEach(group.entries) { entry in
                            FileRow(entry: entry)
                        }
                    }
                    if groups.isEmpty {
                        Text(query.isEmpty ? "Downloads is leeg." : "Niets gevonden.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 320)
            HStack {
                Text("\(folder.entries.count) onderdelen · \(freeSpace) beschikbaar")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open in Finder") {
                    NSWorkspace.shared.open(folder.url)
                    CardPresenter.shared.close()
                }
                .buttonStyle(PillButtonStyle())
            }
        }
        .frame(width: 340)
    }
}

private struct FileRow: View {
    let entry: FileEntry
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                .resizable()
                .frame(width: 24, height: 24)
            Text(entry.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if entry.inProgress {
                ProgressView().controlSize(.mini)
            } else {
                Text(Fmt.bytes(entry.size))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.1 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            NSWorkspace.shared.open(entry.url)
            CardPresenter.shared.close()
        }
        .onDrag { NSItemProvider(contentsOf: entry.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(entry.url) }
            Button("Toon in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
            Button("Kopieer pad") { Clipboard.copy(entry.url.path) }
            Divider()
            Button("Verplaats naar prullenmand") { try? FileManager.default.trashItem(at: entry.url, resultingItemURL: nil) }
        }
    }
}
