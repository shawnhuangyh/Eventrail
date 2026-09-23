import Foundation

/// When this device last read each event's own page from Eventernote.
///
/// What decides whether an event's sheet reads its page again by itself as it
/// opens: a page read within ``freshness`` is shown as held, and an older one
/// is read again while the held copy stays on screen. Opening the same event
/// twice in an afternoon then asks Eventernote nothing the second time, and a
/// start time announced this morning still turns up by tonight without the
/// reader doing anything.
///
/// Only the app's own reading is held to it. Refresh on the Me card is the
/// reader asking, and it reads every page it always has, however recently.
///
/// Kept per device rather than in the archive, the choice ``VenuePlaces`` and
/// ``VenueRegions`` make: this is a note about what this phone has already
/// asked for, not a record the reader owns, so it has no business travelling
/// to their other devices, into a merge, or into a backup.
///
/// **Only a read that landed is written down.** A page that failed is stale,
/// and the next sheet opened on it tries again.
@Observable
final class PageReads {
    static let shared = PageReads()

    /// How old a page may be before its sheet reads it again by itself.
    ///
    /// The same window ``FollowedDates/freshness`` gives a performer's
    /// listing, and for the same reason.
    static let freshness: TimeInterval = 6 * 60 * 60

    /// How long a stamp is kept at all.
    ///
    /// Anything past ``freshness`` says the same thing as no stamp, so the old
    /// ones are dropped rather than left to grow — this lives in
    /// `UserDefaults`, where a library's worth of dates would otherwise sit
    /// forever. A week rather than six hours so that a device offline for a
    /// few days does not come back to a cache it has already thrown away.
    private static let keep: TimeInterval = 7 * 24 * 60 * 60

    private static let cacheKey = "eventPageReads"

    private var reads: [Event.ID: Date]

    /// Previews and the playground pass `persists: false`, so nothing they do
    /// reaches this device's cache.
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    init(persists: Bool = true) {
        self.persists = persists
        reads = persists ? Self.stored : [:]
    }

    deinit { pendingSave?.cancel() }

    /// How many pages this device is holding a read for — what Settings counts
    /// when it says what the cache has in it.
    var count: Int { reads.count }

    /// Whether this event's page was read recently enough to be left alone.
    func isFresh(_ id: Event.ID) -> Bool {
        guard let read = reads[id] else { return false }
        return read.timeIntervalSinceNow > -Self.freshness
    }

    /// Writes down that this event's page has just been read.
    func record(_ id: Event.ID) {
        reads[id] = .now
        save()
    }

    /// Forgets every page this device has read, so every sheet opened next
    /// reads its page again.
    func clear() {
        guard !reads.isEmpty else { return }
        reads = [:]
        pendingSave?.cancel()
        pendingSave = nil
        guard persists else { return }
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
    }

    // MARK: - Where the stamps are kept

    private static var stored: [Event.ID: Date] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return [:] }
        return (try? JSONDecoder().decode([Event.ID: Date].self, from: data)) ?? [:]
    }

    /// Writes after a pause, because a refresh records a page at a time and
    /// hundreds of them in a row — the same coalescing ``EventStore/persist()``
    /// does for a burst of edits.
    private func save() {
        guard persists else { return }
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            // Pruned on the way out rather than on the way in: a run that is
            // still going has better things to do than walk the whole cache
            // once a page.
            let settled = Date.now.addingTimeInterval(-Self.keep)
            reads = reads.filter { $0.value > settled }
            UserDefaults.standard.set(try? JSONEncoder().encode(reads), forKey: Self.cacheKey)
        }
    }
}
