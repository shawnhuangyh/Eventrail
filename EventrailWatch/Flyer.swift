import ImageIO
import SwiftUI

/// An event's flyer, cropped to whatever shape it is drawn in — or the
/// design's empty tile while it loads, and where the event has none.
struct Flyer: View {
    let event: WatchEvent

    @State private var image: CGImage?

    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.14))
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .task(id: event.flyer) {
                image = await FlyerCache.shared.image(for: event)
            }
    }
}

/// The flyers, fetched by the watch itself from the host the phone reads them
/// from — the one host the watch app asks anything of — and kept small.
///
/// Kept per event in Caches, and fetched again after a week: the host files a
/// replaced flyer under the same address, and a watch has no business asking
/// any more often than that. A copy the host fails to answer for stands.
actor FlyerCache {
    static let shared = FlyerCache()

    private nonisolated static let window: TimeInterval = 7 * 24 * 60 * 60
    /// The longest side kept, in pixels — the largest place it is drawn, the
    /// list's 28-point circle, at 2×, with room to spare.
    private nonisolated static let side = 120

    /// Each flyer drawn since launch, with when it was fetched — kept no
    /// longer than one on disk is.
    private var memory: [WatchEvent.ID: (image: CGImage, fetched: Date)] = [:]
    /// A fetch under way, which a second view asking for the same flyer — a
    /// card and the Countdown page appearing together — waits for rather
    /// than fetching it again.
    private var asking: [WatchEvent.ID: Task<CGImage?, Never>] = [:]

    private nonisolated static var folder: URL {
        URL.cachesDirectory.appending(path: "Flyers", directoryHint: .isDirectory)
    }

    private nonisolated static func file(for id: WatchEvent.ID) -> URL {
        folder.appending(path: "\(id).jpg", directoryHint: .notDirectory)
    }

    func image(for event: WatchEvent) async -> CGImage? {
        guard let url = event.flyer else { return nil }
        let id = event.id
        if let held = memory[id], -held.fetched.timeIntervalSinceNow < Self.window { return held.image }
        if let asked = asking[id] { return await asked.value }
        let asked = Task { await read(id, from: url) }
        asking[id] = asked
        let image = await asked.value
        asking[id] = nil
        return image
    }

    /// The copy on disk while it is younger than ``window``, and the host's
    /// otherwise — or the copy on disk where the host does not answer.
    private func read(_ id: WatchEvent.ID, from url: URL) async -> CGImage? {
        let file = Self.file(for: id)
        let kept = (try? Data(contentsOf: file)).flatMap(Self.decoded)
        let fetched = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let kept, let fetched, -fetched.timeIntervalSinceNow < Self.window {
            memory[id] = (kept, fetched)
            return kept
        }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let small = Thumbnail.jpeg(of: data, side: Self.side), let image = Self.decoded(small)
        else { return kept }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? small.write(to: file, options: .atomic)
        memory[id] = (image, .now)
        return image
    }

    /// Throws away the flyers of every event the library no longer holds.
    func keep(only ids: Set<WatchEvent.ID>) {
        memory = memory.filter { ids.contains($0.key) }
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where !ids.contains(file.deletingPathExtension().lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private nonisolated static func decoded(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
