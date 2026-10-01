import CryptoKit
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Event flyers and the linked account's picture, kept on this device once
/// downloaded.
///
/// `AsyncImage` goes through the shared URL cache and nothing else, and the
/// flyer host sends no `Cache-Control` at all — so a flyer scrolled past twice
/// was, often enough, a flyer downloaded twice, and a library of a few hundred
/// rows was a few hundred images fetched again on every visit. So the bytes
/// are written down here the first time, and drawn from here after that.
///
/// **A flyer's address does not change when the flyer does.** The host files
/// each event's artwork under the event's id (`images/events/493541_s.jpg`),
/// so a flyer replaced once the lineup is announced arrives under the same URL
/// as the placeholder it replaces, and a copy kept forever would be the old
/// one forever. What the host does send is an `ETag`. So a copy is drawn with
/// no request at all for ``Freshness/window`` — the six hours everything read
/// from the site keeps — and after that the host is asked whether it has
/// changed: a conditional request whose "no" is no bytes at all rather than
/// the image. A screen refreshed by hand asks again about every flyer on it,
/// however recently — see ``image(for:checkedSince:)``.
///
/// **A copy that has gone stale is still drawn at once.** Asking is done
/// behind it, and the picture changes only if the host sends different
/// bytes — see ``storedImage(for:)``. Waiting on the host first left every
/// flyer a placeholder for as long as the request took each time the window
/// ran out, and for as long as the request took to fail when offline.
///
/// Not the Eventernote site: this host is where the site keeps its images,
/// and is not the one that refuses an app that asks too fast. Everything here
/// is still asked once per image, however many rows want it at once.
actor ImageCache {
    static let shared = ImageCache()

    /// How long a copy nothing has drawn is kept, and how much room all of
    /// them may take between them. Past either, the least recently drawn go
    /// first.
    private static let keep: TimeInterval = 90 * 24 * 60 * 60
    private static let diskLimit = 300 * 1024 * 1024

    /// Decoded and ready to draw, for the rows scrolling past now. Readable
    /// from the main actor without a hop, which is what lets a row that has
    /// been drawn before appear already filled in rather than flashing its
    /// placeholder for a frame. `NSCache` is safe to use from any thread.
    nonisolated(unsafe) private let memory: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 60 * 1024 * 1024
        return cache
    }()

    private let directory: URL
    private let session: URLSession
    /// One download per image, however many rows ask for it at once.
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    /// When the host last vouched for each image held in memory, so a copy
    /// kept decoded past ``Freshness/window`` is asked about again rather
    /// than drawn for the rest of the launch. Only what this launch settled
    /// is here; anything missing goes to the disk to find out.
    private var validated: [URL: Date] = [:]
    /// Bumped by ``clear()``, so a download that was already on its way when
    /// the cache was emptied does not write itself straight back into it.
    private var epoch = 0

    /// What the host said about a copy when it was last asked.
    private struct Validation: Codable {
        var etag: String?
        var checked: Date
    }

    private init() {
        directory = URL.cachesDirectory.appending(path: "Eventrail/Images", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // The copies are this cache's own; the shared URL cache would only
        // hold every one of them a second time.
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        let directory = directory
        Task.detached(priority: .background) { Self.prune(directory) }
    }

    // MARK: - Asking for an image

    /// An image already decoded and in memory, or nil — asked synchronously as
    /// a view is built, so a row drawn before draws filled in.
    nonisolated func memoryImage(for url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    /// A copy this device already holds, from memory or from disk, without
    /// asking the host anything — however long ago it was last asked.
    ///
    /// What a view draws first, so a stale flyer is on screen while
    /// ``image(for:checkedSince:)`` asks about it rather than a placeholder.
    func storedImage(for url: URL) -> UIImage? {
        if let image = memory.object(forKey: url as NSURL) { return image }
        let (file, _) = paths(for: url)
        guard let stored = try? Data(contentsOf: file) else { return nil }
        return remember(stored, for: url)
    }

    /// The image at `url`: from memory, from this device, or downloaded — in
    /// that order, and each downloaded once however many ask.
    ///
    /// A copy the host vouches for again comes back as the very object
    /// already held in memory, so a view can tell "unchanged" from "new" by
    /// identity and leave the picture alone.
    ///
    /// `checkedSince` is when the screen around it was last refreshed by hand.
    /// A copy whose host was last asked before then is asked about again —
    /// which is how a pull resets the six hours on the flyers as well as the
    /// rows — and one asked since is drawn as it is.
    func image(for url: URL, checkedSince: Date? = nil) async -> UIImage? {
        if let image = memory.object(forKey: url as NSURL), let checked = validated[url],
           checked > Self.deadline(checkedSince) {
            return image
        }
        return await join(url) { await self.load(url, checkedSince: checkedSince) }
    }

    /// The image at `url` as a file of its own, the host's bytes as sent,
    /// named `name` with the extension those bytes call for — what Quick Look
    /// and the share sheet are handed, since both go by a file's name and kind
    /// and the copy kept here has neither. Fetched first as
    /// ``image(for:checkedSince:)`` would, and nil where no copy can be had.
    ///
    /// Written into the temporary directory, one folder per image, and
    /// written again each time: the flyer and the name may both have changed.
    func file(for url: URL, named name: String, checkedSince: Date? = nil) async -> URL? {
        _ = await image(for: url, checkedSince: checkedSince)
        let (stored, _) = paths(for: url)
        guard let data = try? Data(contentsOf: stored) else { return nil }
        let kind = CGImageSourceCreateWithData(data as CFData, nil)
            .flatMap(CGImageSourceGetType)
            .flatMap { UTType($0 as String) }
        let fileExtension = kind?.preferredFilenameExtension
            ?? (url.pathExtension.isEmpty ? "jpg" : url.pathExtension)
        let folder = URL.temporaryDirectory.appending(path: "Flyers/\(stored.lastPathComponent)", directoryHint: .isDirectory)
        let file = folder.appending(path: Self.fileName(name)).appendingPathExtension(fileExtension)
        do {
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            return file
        } catch {
            return nil
        }
    }

    /// `name` as a file name: no slash or colon, and short enough in bytes
    /// for the extension to fit after it.
    private static func fileName(_ name: String) -> String {
        var kept = ""
        for character in name.replacing(/[\/:]/, with: "-").trimmingCharacters(in: .whitespacesAndNewlines) {
            guard kept.utf8.count + character.utf8.count <= 200 else { break }
            kept.append(character)
        }
        return kept.isEmpty ? "Flyer" : kept
    }

    /// Throws every copy away, from memory and from this device.
    func clear() {
        epoch += 1
        for task in inFlight.values { task.cancel() }
        inFlight = [:]
        validated = [:]
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func join(_ url: URL, _ work: @escaping @Sendable () async -> UIImage?) async -> UIImage? {
        if let running = inFlight[url] { return await running.value }
        let task = Task { await work() }
        inFlight[url] = task
        let image = await task.value
        // Only this download's own entry: a clear in the meantime may have
        // let a new one start under the same address.
        if inFlight[url] == task { inFlight[url] = nil }
        return image
    }

    // MARK: - Reading, asking, writing

    /// Asked about within the window, and since any refresh by hand: drawn
    /// as it is.
    private static func deadline(_ checkedSince: Date?) -> Date {
        max(Date.now.addingTimeInterval(-Freshness.window), checkedSince ?? .distantPast)
    }

    private func load(_ url: URL, checkedSince: Date?) async -> UIImage? {
        let epoch = epoch
        let (file, sidecar) = paths(for: url)
        let stored = try? Data(contentsOf: file)
        let validation = (try? Data(contentsOf: sidecar))
            .flatMap { try? JSONDecoder().decode(Validation.self, from: $0) }

        if let stored {
            // Drawn now, so it is the last to go when room is short.
            try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: file.path)
            if let validation, validation.checked > Self.deadline(checkedSince) {
                validated[url] = validation.checked
                return memory.object(forKey: url as NSURL) ?? remember(stored, for: url)
            }
        }

        var request = URLRequest(url: url)
        if stored != nil, let etag = validation?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        do {
            let (data, response) = try await session.data(for: request)
            // Cleared while this was on its way: what it brought is drawn for
            // whoever asked, and kept nowhere.
            guard epoch == self.epoch else { return UIImage(data: data) }
            let http = response as? HTTPURLResponse
            // Unchanged, whether the host says so or sends the same bytes
            // again: the copy already drawn stays, rather than being decoded
            // a second time and swapped for an identical picture.
            if let stored, http?.statusCode == 304 || (http?.statusCode == 200 && data == stored) {
                let etag = http?.statusCode == 200 ? http?.value(forHTTPHeaderField: "ETag") : validation?.etag
                write(Validation(etag: etag ?? validation?.etag, checked: .now), to: sidecar)
                validated[url] = .now
                return memory.object(forKey: url as NSURL) ?? remember(stored, for: url)
            }
            guard http?.statusCode == 200, let image = remember(data, for: url) else {
                // Anything else — a missing flyer, a host having a bad moment —
                // leaves the copy already held, if there is one.
                return memory.object(forKey: url as NSURL) ?? stored.flatMap { remember($0, for: url) }
            }
            try? data.write(to: file, options: .atomic)
            write(Validation(etag: http?.value(forHTTPHeaderField: "ETag"), checked: .now), to: sidecar)
            validated[url] = .now
            return image
        } catch {
            // Offline: the copy held is the best there is.
            guard epoch == self.epoch else { return nil }
            return memory.object(forKey: url as NSURL) ?? stored.flatMap { remember($0, for: url) }
        }
    }

    /// Decodes the bytes once, ready to draw, and keeps the result in memory.
    /// Decoded here rather than as the row draws, which is what keeps a list
    /// of flyers from stuttering as it scrolls.
    private func remember(_ data: Data, for url: URL) -> UIImage? {
        guard let image = UIImage(data: data)?.preparingForDisplay() ?? UIImage(data: data) else { return nil }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? data.count
        memory.setObject(image, forKey: url as NSURL, cost: cost)
        return image
    }

    private func write(_ validation: Validation, to sidecar: URL) {
        try? JSONEncoder().encode(validation).write(to: sidecar, options: .atomic)
    }

    /// Named by a digest of the address, with what the host said about it
    /// beside it.
    private func paths(for url: URL) -> (image: URL, sidecar: URL) {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return (directory.appending(path: digest), directory.appending(path: "\(digest).json"))
    }

    /// Drops what nothing has drawn in ``keep``, then the least recently drawn
    /// until everything fits in ``diskLimit``.
    private static func prune(_ directory: URL) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let files = ((try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys)) ?? [])
            .filter { $0.pathExtension != "json" }
        var kept: [(file: URL, used: Date, size: Int)] = []
        let settled = Date.now.addingTimeInterval(-keep)
        for file in files {
            let values = try? file.resourceValues(forKeys: Set(keys))
            let used = values?.contentModificationDate ?? .distantPast
            if used < settled {
                remove(file)
            } else {
                kept.append((file, used, values?.fileSize ?? 0))
            }
        }
        var total = kept.reduce(0) { $0 + $1.size }
        for entry in kept.sorted(by: { $0.used < $1.used }) where total > diskLimit {
            remove(entry.file)
            total -= entry.size
        }
    }

    private static func remove(_ file: URL) {
        try? FileManager.default.removeItem(at: file)
        try? FileManager.default.removeItem(at: file.appendingPathExtension("json"))
    }
}
