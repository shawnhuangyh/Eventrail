import ImageIO
import SwiftUI
import UniformTypeIdentifiers

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

    private var memory: [WatchEvent.ID: CGImage] = [:]

    private nonisolated static var folder: URL {
        URL.cachesDirectory.appending(path: "Flyers", directoryHint: .isDirectory)
    }

    private nonisolated static func file(for id: WatchEvent.ID) -> URL {
        folder.appending(path: "\(id).jpg", directoryHint: .notDirectory)
    }

    func image(for event: WatchEvent) async -> CGImage? {
        guard let url = event.flyer else { return nil }
        if let image = memory[event.id] { return image }
        let file = Self.file(for: event.id)
        let kept = (try? Data(contentsOf: file)).flatMap(Self.decoded)
        let age = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate.map { -$0.timeIntervalSinceNow }
        if let kept, let age, age < Self.window {
            memory[event.id] = kept
            return kept
        }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let small = Self.downsized(data), let image = Self.decoded(small)
        else { return kept }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? small.write(to: file, options: .atomic)
        memory[event.id] = image
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

    private nonisolated static func downsized(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: side,
              ] as CFDictionary)
        else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}
