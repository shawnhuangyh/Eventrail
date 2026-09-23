import CryptoKit
import Foundation

/// A performer's or a hall's page as this device last read it: who or what it
/// is, and the front of its listing.
///
/// "The front" is every page up to and including the first one carrying a
/// past row — the whole of the upcoming half, since the site orders a listing
/// from the furthest published date backwards — plus whatever the reader
/// scrolled on to since. Nothing past that is ever read on the reader's
/// behalf.
nonisolated struct CachedListing<Subject: Codable & Sendable>: Codable, Sendable {
    var subject: Subject
    var items: [Event]
    var total: Int
    var pagesRead: Int
    var hasMore: Bool
    /// When the front of the listing was read. Pages scrolled on to later do
    /// not move it: the front is the part that goes stale.
    var readAt: Date

    /// Whether opening the page may show this and ask nothing.
    var isFresh: Bool { readAt.timeIntervalSinceNow > -ListingCache.freshness }
}

/// What this device last read of each performer's and each hall's page.
///
/// The same arrangement ``FollowedDates`` has for the Following tab and
/// ``PageReads`` for an event's sheet, and for the same reason: a performer
/// page cost a search for the name and then page after page of listing every
/// time it was opened, and opening the same three performers from three
/// different events was asking Eventernote for the same pages three times in a
/// minute. So a page is shown from here at once; read again by itself only
/// once it is ``freshness`` old; and read on the spot whenever the reader pulls
/// it down.
///
/// One file per page, in Caches: a listing is a few dozen events, there are as
/// many of them as pages the reader has opened, and the system is welcome to
/// take them back when the device is short of room. Kept per device and never
/// synced, like every other copy of the site's facts.
@Observable
final class ListingCache {
    static let shared = ListingCache()

    /// How old a page may be before opening it reads it again by itself — the
    /// window ``FollowedDates/freshness`` and ``PageReads/freshness`` keep too.
    nonisolated static let freshness = Freshness.window

    /// How long a page nobody has opened is kept at all. A performer looked at
    /// once from a search and never again stops taking up room.
    private static let keep: TimeInterval = 30 * 24 * 60 * 60

    /// How many pages are held — what Settings counts.
    private(set) var count = 0

    @ObservationIgnored private let directory: URL

    private init() {
        directory = URL.cachesDirectory.appending(path: "Eventrail/Listings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        count = Self.prune(directory)
    }

    // MARK: - Reading and writing

    func entry<Subject: Codable & Sendable>(for key: String, as: Subject.Type) -> CachedListing<Subject>? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        // A copy written by a build that read the page differently simply
        // fails to decode, and the page is read afresh.
        return try? JSONDecoder().decode(CachedListing<Subject>.self, from: data)
    }

    /// Written at once rather than after a pause: a page is written when a
    /// read lands or the reader scrolls a page further, both rare, and a
    /// listing is small enough to encode between frames.
    func store<Subject: Codable & Sendable>(_ entry: CachedListing<Subject>, for key: String) {
        let url = url(for: key)
        let isNew = !FileManager.default.fileExists(atPath: url.path)
        guard (try? JSONEncoder().encode(entry).write(to: url, options: .atomic)) != nil else { return }
        if isNew { count += 1 }
    }

    /// Writes down the pages the reader has scrolled on to since the last read,
    /// so the next visit opens on them too. The time of the read is kept.
    func extend<Subject: Codable & Sendable>(_ key: String, as: Subject.Type, with feed: Feed<Event>) {
        guard var entry = entry(for: key, as: Subject.self), feed.page > entry.pagesRead else { return }
        entry.items = feed.items
        entry.total = feed.total
        entry.pagesRead = feed.page
        entry.hasMore = feed.hasMore
        store(entry, for: key)
    }

    /// Throws every page away, so each is read afresh the next time it opens.
    func clear() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        count = 0
    }

    /// Named by a digest of the key rather than the key itself: a key carries a
    /// hall's or a performer's name, which is Japanese, often long, and
    /// sometimes holds characters a file name should not.
    private func url(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(digest).json")
    }

    /// Drops the pages nobody has opened in ``keep``, and says how many are left.
    private static func prune(_ directory: URL) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let settled = Date.now.addingTimeInterval(-keep)
        var kept = 0
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if modified < settled {
                try? FileManager.default.removeItem(at: file)
            } else {
                kept += 1
            }
        }
        return kept
    }
}

// MARK: - Reading a page from the site

extension ListingCache {
    /// How one read of a page went.
    enum Read<Subject: Codable & Sendable>: Sendable {
        case read(CachedListing<Subject>)
        /// The site files nobody, or no hall, under the name the page was
        /// opened with — an answer, not a failure.
        case unlisted
        case failed(String)
    }

    /// Reads who or what a page is about and the front of its listing: pages
    /// from the first until one carries a past row, which proves the whole of
    /// the upcoming half is in hand.
    ///
    /// **In a task of its own, out of reach of the caller's cancellation** —
    /// the lesson of an event's sheet, where SwiftUI cancelling a pull's
    /// refresh action reached the request and the pull ended in no answer and
    /// no error. A read that outlives its page still lands in the cache.
    ///
    /// Stops at the first page that fails, which is also what makes a
    /// refusal for asking too often end the run rather than extend it.
    static func read<Subject: Codable & Sendable>(
        subject resolve: @escaping @Sendable () async throws -> Subject?,
        listing: @escaping @Sendable (Subject, Int) async throws -> EventernotePage<Event>
    ) async -> Read<Subject> {
        await Task { () -> Read<Subject> in
            do {
                guard let subject = try await resolve() else { return .unlisted }
                var items: [Event] = []
                var known: Set<Event.ID> = []
                var page = 0
                var total = 0
                var hasMore = true
                while hasMore {
                    page += 1
                    let result = try await listing(subject, page)
                    let arrived = result.items.filter { known.insert($0.id).inserted }
                    items += arrived
                    total = result.total
                    hasMore = result.hasMore
                    // A page that adds nothing would otherwise spin here
                    // forever; a past row means the upcoming half is whole.
                    if arrived.isEmpty || items.contains(where: { !$0.isUpcoming }) { break }
                }
                return .read(CachedListing(subject: subject, items: items, total: total,
                                           pagesRead: page, hasMore: hasMore, readAt: .now))
            } catch {
                return .failed(error.localizedDescription)
            }
        }.value
    }
}

// MARK: - What each page is filed under

nonisolated extension PerformerLink {
    /// By actor id where the page was opened with one, and by the billed name
    /// where it was not — the name is all a billing publishes, and resolving
    /// it again is one of the requests the cache is there to save.
    var cacheKey: String {
        switch self {
        case .profile(let profile): "performer/\(profile.id)"
        case .billed(let name): "performer/named/\(name)"
        }
    }
}

nonisolated extension VenueLink {
    var cacheKey: String {
        switch self {
        case .place(let listing): "venue/\(listing.id)"
        case .named(let name): "venue/named/\(name)"
        }
    }
}
