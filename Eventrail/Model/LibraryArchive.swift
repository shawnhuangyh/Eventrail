import Foundation
import OSLog

/// A value and when it last changed.
///
/// Two devices edit the same library with nothing arbitrating between them, so
/// every record the reader owns carries the moment it was written. A merge takes
/// the newer of two edits rather than the newer of two whole files, which is
/// what keeps a note typed on one device from being erased by an unrelated
/// change made on the other.
struct Stamped<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    var value: Value
    var modified: Date

    init(_ value: Value, at modified: Date = .now) {
        self.value = value
        self.modified = modified
    }

    /// The newer of the two. Ties keep `self`, so a merge is stable when two
    /// devices happen to write in the same instant.
    func newer(_ other: Stamped) -> Stamped {
        other.modified > modified ? other : self
    }
}

/// Everything the reader has accumulated, in the form it is written to disk and
/// handed to iCloud.
///
/// Imported event facts and the reader's own records are kept apart: ``events``
/// is replaced wholesale by an import, while ``tracking``, ``membership`` and
/// ``favorites`` are only ever written by the reader and are merged, never
/// overwritten.
struct LibraryArchive: Codable, Sendable {
    /// Every event worth remembering, keyed by Eventernote's id — the library,
    /// plus anything favorited that is not in it.
    var events: [Event.ID: Event] = [:]
    /// Whether each event is in the library. A `false` entry is a tombstone: a
    /// removal has to travel to the other device too, or it would be undone by
    /// the next merge.
    var membership: [Event.ID: Stamped<Bool>] = [:]
    var tracking: [Event.ID: Stamped<Tracking>] = [:]
    var favorites: [Event.ID: Stamped<Bool>] = [:]
    var recentSearches: Stamped<[String]> = Stamped([], at: .distantPast)
    var lastRefreshed: Date?

    /// The library itself, in no particular order — every screen sorts it.
    var libraryEvents: [Event] {
        membership.compactMap { $0.value.value ? events[$0.key] : nil }
    }

    func isInLibrary(_ id: Event.ID) -> Bool { membership[id]?.value == true }
    func isFavorite(_ id: Event.ID) -> Bool { favorites[id]?.value == true }

    /// Folds another device's archive into this one.
    ///
    /// The reader's records merge record by record, newest edit winning. Event
    /// facts are not the reader's, so the more complete import wins and no
    /// timestamp is needed for them.
    func merging(_ other: LibraryArchive) -> LibraryArchive {
        var merged = self

        for (id, event) in other.events {
            guard let mine = merged.events[id] else {
                merged.events[id] = event
                continue
            }
            // Both are imports of the same public page, so either is true. The
            // one that read the event's own page carries more of it.
            merged.events[id] = mine.isDetailed ? mine.merging(event) : event.merging(mine)
        }

        merged.membership = Self.merge(membership, other.membership)
        merged.tracking = Self.merge(tracking, other.tracking)
        merged.favorites = Self.merge(favorites, other.favorites)
        merged.recentSearches = recentSearches.newer(other.recentSearches)
        merged.lastRefreshed = [lastRefreshed, other.lastRefreshed].compactMap { $0 }.max()

        return merged.pruned()
    }

    private static func merge<Value>(
        _ mine: [Event.ID: Stamped<Value>], _ theirs: [Event.ID: Stamped<Value>]
    ) -> [Event.ID: Stamped<Value>] {
        mine.merging(theirs) { $0.newer($1) }
    }

    /// Drops what neither device needs to keep agreeing on: long-settled
    /// tombstones, and events nothing points at any more.
    func pruned() -> LibraryArchive {
        var pruned = self
        let settled = Date.now.addingTimeInterval(-180 * 24 * 60 * 60)

        pruned.membership = membership.filter { $0.value.value || $0.value.modified > settled }
        pruned.favorites = favorites.filter { $0.value.value || $0.value.modified > settled }
        pruned.events = events.filter { pruned.isInLibrary($0.key) || pruned.isFavorite($0.key) }
        pruned.tracking = tracking.filter {
            // A note survives its event leaving the library; an empty record does not.
            !$0.value.value.isEmpty || $0.value.modified > settled
        }
        return pruned
    }
}

/// Keeps the archive in a JSON file inside the app's container.
///
/// Not SwiftData: the project defers that schema until it is settled, and this
/// keeps what the reader adds across launches in the meantime without
/// committing to a store.
nonisolated struct LibraryFile: Sendable {
    static let shared = LibraryFile()

    private static let log = Logger(subsystem: "com.shawnhuang.Eventrail", category: "library")

    var url: URL = {
        let directory = URL.applicationSupportDirectory.appending(path: "Eventrail", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "library.json")
    }()

    /// An unreadable file yields an empty library rather than a crash: the
    /// reader can always add events again, and a refusal to launch helps nobody.
    func load() -> LibraryArchive {
        guard let data = try? Data(contentsOf: url) else { return LibraryArchive() }
        if let archive = try? JSONDecoder().decode(LibraryArchive.self, from: data) {
            return archive
        }
        // The first shipped format had no timestamps on it. Rather than drop a
        // library that predates syncing, read it and stamp it as it stands.
        if let legacy = try? JSONDecoder().decode(LegacyArchive.self, from: data) {
            Self.log.notice("Migrating a pre-sync library file.")
            return legacy.migrated()
        }
        Self.log.error("Library file could not be read; starting empty.")
        return LibraryArchive()
    }

    func save(_ archive: LibraryArchive) {
        do {
            try JSONEncoder().encode(archive).write(to: url, options: .atomic)
        } catch {
            Self.log.error("Library file could not be written: \(error.localizedDescription)")
        }
    }
}

/// The archive as it was written before records carried timestamps.
private struct LegacyArchive: Codable {
    var events: [Event] = []
    var tracking: [Event.ID: Tracking] = [:]
    var favorites: Set<Event.ID> = []
    var recentSearches: [String] = []
    var lastRefreshed: Date?

    func migrated() -> LibraryArchive {
        // Everything predates the first sync, so it loses to any later edit on
        // another device — which is the right way round for a one-device history.
        let when = Date.now
        var archive = LibraryArchive()
        archive.events = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        archive.membership = events.reduce(into: [:]) { $0[$1.id] = Stamped(true, at: when) }
        archive.tracking = tracking.mapValues { Stamped($0, at: when) }
        archive.favorites = favorites.reduce(into: [:]) { $0[$1] = Stamped(true, at: when) }
        archive.recentSearches = Stamped(recentSearches, at: when)
        archive.lastRefreshed = lastRefreshed
        return archive
    }
}
