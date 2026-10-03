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
    static let freshness = Freshness.window

    /// How long a stamp is kept at all.
    ///
    /// Anything past ``freshness`` says the same thing as no stamp, so the old
    /// ones are dropped rather than left to grow, where a library's worth of
    /// dates would otherwise sit forever. A week rather than six hours so that
    /// a device offline for a few days does not come back to a cache it has
    /// already thrown away.
    private static let keep: TimeInterval = 7 * 24 * 60 * 60

    private var reads: [Event.ID: Date]
    /// When the stamps were last thrown away. A read already on its way then
    /// — a Refresh on the Me card is hundreds of them — lands afterwards, and
    /// stamping it would leave that page fresh straight through the clear.
    @ObservationIgnored private var clearedAt = Date.distantPast

    /// In Caches: every stamp says only that a page need not be read again
    /// yet, and losing one costs a single read. Nil in previews and the
    /// playground, which pass `persists: false`, so nothing they do reaches
    /// this device's cache.
    @ObservationIgnored private let file: KeptFile<Event.ID, Date>?

    init(persists: Bool = true) {
        let file = persists
            ? KeptFile<Event.ID, Date>(named: "pageReads.json", in: .caches, formerKey: "eventPageReads")
            : nil
        self.file = file
        // Pruned on the way in rather than on the way out: a run still going
        // has better things to do than walk the whole cache once a page.
        let settled = Date.now.addingTimeInterval(-Self.keep)
        reads = (file?.read() ?? [:]).filter { $0.value > settled }
    }

    /// Whether this event's page was read recently enough to be left alone.
    func isFresh(_ id: Event.ID) -> Bool {
        guard let read = reads[id] else { return false }
        return read.timeIntervalSinceNow > -Self.freshness
    }

    /// When this device last read this event's page, if within the week a
    /// stamp is kept.
    func lastRead(_ id: Event.ID) -> Date? {
        reads[id]
    }

    /// Writes down that this event's page has just been read — unless the
    /// stamps were cleared after it was asked for, `asked` being when.
    func record(_ id: Event.ID, asked: Date) {
        guard asked >= clearedAt else { return }
        reads[id] = .now
        save()
    }

    /// Forgets every page this device has read, so every sheet opened next
    /// reads its page again.
    func clear() {
        clearedAt = .now
        guard !reads.isEmpty else { return }
        reads = [:]
        file?.remove()
    }

    private func save() {
        file?.write(&reads)
    }
}
