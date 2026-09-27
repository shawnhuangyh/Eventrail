import Foundation
import os

/// A dictionary this device keeps for itself in a JSON file of its own: what
/// ``VenuePlaces``, ``VenueRegions`` and ``PageReads`` have found out.
///
/// All three used to live in `UserDefaults`, which is for preferences — the
/// whole store is read into memory as the app starts — and ``VenuePlaces``
/// decoded and re-encoded every hall it had ever placed there, on the main
/// actor, each time it looked one up. Each is now read once, held by its
/// owner, and written a moment after the last change, off the main actor: the
/// way ``FollowedDates`` and ``ListingCache`` already kept theirs. Whatever a
/// build that kept it in `UserDefaults` left there is moved across on the
/// first read, and the key dropped once the file holds it.
///
/// **A file that is there and will not open is never written over.** A device
/// not yet unlocked since it started refuses to open it, and writing the few
/// answers such a launch finds over it would throw away everything it held.
/// So until a read gets through, nothing is written; each write tries the file
/// again, and once it opens, what it held is folded in beneath what the launch
/// found since — the rule ``LibraryFile`` keeps for the library. A file that
/// opens and will not decode is a cache in an older shape, and is read as
/// empty and written over, as it always was.
final class KeptFile<Key: Codable & Hashable & Sendable, Value: Codable & Sendable> {
    /// Where the file lives, which is how much losing it would cost.
    enum Place {
        /// Kept through a device running short of room: what it holds took
        /// hundreds of requests to gather.
        case applicationSupport
        /// All of it can be read again, so the system may take it back.
        case caches
    }

    private let url: URL
    /// Where a build before this one kept the same dictionary.
    private let formerKey: String
    private let defaults: UserDefaults
    private let log = Logger(subsystem: "moe.shawn.Eventrail", category: "storage")
    /// Whether the file was there at the last read and would not open.
    private var isBlocked = false
    private var pendingWrite: Task<Void, Never>?
    /// The last write or removal handed to the disk. Each waits for the one
    /// before it, so a removal is never overtaken by a write begun earlier.
    private var lastOperation: Task<Void, Never>?

    convenience init(named name: String, in place: Place, formerKey: String) {
        let base: URL = switch place {
        case .applicationSupport: .applicationSupportDirectory
        case .caches: .cachesDirectory
        }
        let directory = base.appending(path: "Eventrail", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.init(url: directory.appending(path: name), formerKey: formerKey, defaults: .standard)
    }

    /// A file anywhere, its former key in any defaults — which is how the
    /// tests make one.
    init(url: URL, formerKey: String, defaults: UserDefaults) {
        self.url = url
        self.formerKey = formerKey
        self.defaults = defaults
    }

    /// What the file holds — empty where there is none yet, and empty while it
    /// will not open, which ``write(_:)`` then answers for.
    func read() -> [Key: Value] {
        var contents: [Key: Value] = [:]
        do {
            contents = Self.decode(try Data(contentsOf: url))
            isBlocked = false
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            isBlocked = false
        } catch {
            log.error("\(self.url.lastPathComponent, privacy: .public) would not open: \(error.localizedDescription, privacy: .public)")
            isBlocked = true
        }
        // Folded in beneath the file rather than only read where there is no
        // file: a launch that could not read `UserDefaults` either may have
        // written a file of its own since.
        if let former = defaults.data(forKey: formerKey) {
            contents = Self.decode(former).merging(contents) { _, kept in kept }
            if !isBlocked, (try? JSONEncoder().encode(contents).write(to: url, options: .atomic)) != nil {
                defaults.removeObject(forKey: formerKey)
            }
        }
        return contents
    }

    /// Writes `contents` a moment from now, so a burst of changes is one write.
    ///
    /// Where the last read was refused, the file is tried again first: still
    /// refused, nothing is written; opened, what it holds is folded into
    /// `contents` beneath what is already there, and that is what is written.
    func write(_ contents: inout [Key: Value]) {
        if isBlocked {
            let held = read()
            guard !isBlocked else { return }
            contents = held.merging(contents) { _, found in found }
        }
        pendingWrite?.cancel()
        let snapshot = contents
        pendingWrite = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            enqueue { url in
                try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            }
        }
    }

    /// Throws the file away, and any write still waiting to be made.
    func remove() {
        pendingWrite?.cancel()
        pendingWrite = nil
        isBlocked = false
        enqueue { url in
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Waits until every write and removal handed over so far is on disk.
    func settled() async {
        await pendingWrite?.value
        await lastOperation?.value
    }

    private func enqueue(_ operation: @escaping @Sendable (URL) throws -> Void) {
        let previous = lastOperation
        let url = url
        let log = log
        lastOperation = Task.detached(priority: .utility) {
            await previous?.value
            do {
                try operation(url)
            } catch {
                log.error("\(url.lastPathComponent, privacy: .public) could not be written: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private nonisolated static func decode(_ data: Data) -> [Key: Value] {
        (try? JSONDecoder().decode([Key: Value].self, from: data)) ?? [:]
    }
}
