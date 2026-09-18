import Foundation
import SwiftUI

/// Which slice of the library the Events tab shows.
enum LibraryFilter: String, CaseIterable, Identifiable, Hashable {
    case upcoming, past

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .upcoming: "Upcoming"
        case .past: "Past"
        }
    }

    /// The glyph beside the option in the Filter menu: a plain clock for what
    /// is ahead, the rewound one for what has already happened.
    var symbol: String {
        switch self {
        case .upcoming: "clock"
        case .past: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        }
    }
}

/// How the Events tab breaks the list into sections.
///
/// By date means by month: the library reads as a run of months, and an
/// ungrouped list of everything was the same thing with its signposts taken
/// away.
enum Grouping: String, CaseIterable, Identifiable, Hashable {
    case date, artist

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .date: "Date"
        case .artist: "Artist"
        }
    }

    /// The glyph beside the option in the Sort menu.
    var symbol: String {
        switch self {
        case .date: "calendar"
        case .artist: "music.mic"
        }
    }
}

/// Which of Eventernote's two searches the Search tab is running.
enum SearchScope: String, CaseIterable, Identifiable, Hashable {
    case events, performers

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .events: "Events"
        case .performers: "Performers"
        }
    }
}

/// One section of the Events list.
struct EventGroup: Identifiable {
    let id: String
    /// Imported names (artists) and formatted dates, so not a localizable key.
    let label: String
    let events: [Event]
}

/// The reader's library, and every write to it.
///
/// Imported facts and the reader's own records are kept strictly apart: an
/// import replaces ``LibraryArchive/events`` and never reads or writes tracking,
/// membership or favorites. Every change is mirrored to ``LibraryFile`` so it
/// survives the app closing, and — when the reader has it switched on — pushed
/// to ``CloudSync`` so their other devices see it.
@Observable
final class EventStore {
    /// Everything the reader owns. Kept as one value so a merge from another
    /// device is a single, reviewable operation rather than a dozen assignments.
    private var archive: LibraryArchive

    private(set) var isRefreshing = false
    /// Why the last import stopped short, if it did. A failed import keeps the
    /// previous snapshot and the timestamp that goes with it.
    private(set) var refreshFailure: String?

    private(set) var syncStatus: CloudSync.Outcome?
    private(set) var lastSynced: Date?

    /// What a refresh is doing at this moment. Reading a nine-page history and
    /// re-reading nine hundred event pages take very different amounts of time,
    /// so the screen says which one it is waiting on rather than just spinning.
    private(set) var refreshStage: RefreshStage?
    /// What the last refresh imported from the linked account, kept only for as
    /// long as the screen shows it.
    private(set) var importSummary: ImportSummary?

    enum RefreshStage: Hashable {
        /// Paging the linked account's own list. `total` is 0 until the site
        /// has said how long the list is.
        case readingHistory(read: Int, total: Int)
        case reimporting(read: Int, total: Int)
    }

    /// What one import changed. `added` and `filled` are counted separately
    /// because they are different promises: one grew the library, the other only
    /// wrote a tracking field the reader had left alone.
    ///
    /// A summary and a ``refreshFailure`` can both be set: a history that read
    /// six pages of nine still adopted those six.
    struct ImportSummary: Hashable {
        var read: Int
        var added: Int
        var filled: Int
        /// Performers newly followed from the account's own favourites, which
        /// come off the member page rather than out of the history.
        var followed: Int = 0
    }

    /// Whether this device mirrors the library to iCloud. A per-device choice,
    /// so it deliberately does not sync: turning sync off on a phone should not
    /// turn it off on the iPad.
    var iCloudSyncEnabled: Bool {
        didSet {
            guard iCloudSyncEnabled != oldValue else { return }
            UserDefaults.standard.set(iCloudSyncEnabled, forKey: Self.syncPreferenceKey)
            if iCloudSyncEnabled {
                Task { await syncNow() }
            } else {
                syncStatus = nil
            }
        }
    }

    private static let syncPreferenceKey = "iCloudSyncEnabled"

    /// Whether this device asks OpenStreetMap which building at the published
    /// address is the hall — see ``VenueBuildings``.
    ///
    /// Held here rather than read straight off ``VenuePlaces`` so that a
    /// switch on a screen redraws when it is thrown; the preference itself
    /// lives there, per device, along with the answers it produces.
    var preciseVenuesEnabled: Bool {
        didSet {
            guard preciseVenuesEnabled != oldValue else { return }
            venues?.usesOpenStreetMap = preciseVenuesEnabled
        }
    }

    /// Whether this device copies ticketed events into the reader's calendar.
    ///
    /// Per-device for the same reason ``iCloudSyncEnabled`` is, and then some:
    /// the calendar Eventrail writes to is this device's, and the permission
    /// behind it was granted on this device alone.
    ///
    /// Off by default, and off is quiet: until the reader turns this on, the
    /// app never reaches EventKit at all. Only two calls ask for calendar
    /// permission — ``CalendarSync/mirror(_:)``, which ``mirrorCalendar()``
    /// reaches only while this is true, and ``CalendarSync/stop()``, which
    /// returns before asking unless a calendar of the app's own was actually
    /// made. So the system's permission sheet is the answer to this switch and
    /// to nothing else. Writing to someone's calendar is not something to
    /// start doing on their behalf, and asking for the right to is not either.
    var calendarSyncEnabled: Bool {
        didSet {
            guard calendarSyncEnabled != oldValue else { return }
            UserDefaults.standard.set(calendarSyncEnabled, forKey: Self.calendarPreferenceKey)
            Task { await mirrorCalendar() }
        }
    }

    private static let calendarPreferenceKey = "calendarSyncEnabled"

    /// What the last mirror to the calendar did, or why it could not. Nil until
    /// one has run.
    private(set) var calendarStatus: CalendarSync.Outcome?

    /// What a refresh of the venues is doing, or what the last one did. Nil
    /// until the reader asks for one.
    private(set) var venueStatus: VenuePlaces.Refresh?

    /// Whether one is running now. The button that starts it says so, and does
    /// not start a second.
    var isRefreshingVenues: Bool {
        if case .asking = venueStatus { return true }
        return false
    }

    /// Events met in search but never added. Transient: they are not the
    /// reader's, so they are neither saved nor synced until one is kept.
    private var seen: [Event.ID: Event] = [:]

    private let file: LibraryFile?
    private let cloud: CloudSync?
    private let calendar: CalendarSync?
    private let venues: VenuePlaces?
    private let client: EventernoteClient
    private var pendingSave: Task<Void, Never>?
    private var cloudChanges: Task<Void, Never>?
    private var venuePlacings: Task<Void, Never>?
    private var pendingMirror: Task<Void, Never>?

    /// The default store reads the reader's own library from disk and, if they
    /// have sync on, merges whatever iCloud holds. Previews and the playground
    /// pass events in and leave `file` and `cloud` nil, so nothing they do is
    /// written or synced anywhere.
    init(
        file: LibraryFile? = .shared,
        cloud: CloudSync? = .shared,
        calendar: CalendarSync? = .shared,
        venues: VenuePlaces? = .shared,
        client: EventernoteClient = .shared,
        library: [Event] = [],
        tracking: [Event.ID: Tracking] = [:],
        follows: [PerformerProfile] = []
    ) {
        self.file = file
        self.cloud = cloud
        self.calendar = calendar
        self.venues = venues
        self.client = client

        // On by default: a reader with more than one device expects their own
        // records to follow them. A preview has no file and never syncs.
        iCloudSyncEnabled = file != nil
            && (UserDefaults.standard.object(forKey: Self.syncPreferenceKey) as? Bool ?? true)
        calendarSyncEnabled = calendar != nil
            && UserDefaults.standard.bool(forKey: Self.calendarPreferenceKey)
        preciseVenuesEnabled = venues?.usesOpenStreetMap ?? false

        var loaded = file?.load() ?? LibraryArchive()
        if loaded.membership.isEmpty, !library.isEmpty {
            loaded.events = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            loaded.membership = library.reduce(into: [:]) { $0[$1.id] = Stamped(true) }
            loaded.tracking = tracking.mapValues { Stamped($0) }
        }
        if loaded.follows == nil, !follows.isEmpty {
            loaded.follows = follows.reduce(into: [:]) { $0[String($1.id)] = Stamped(true) }
            loaded.followedPerformers = follows.reduce(into: [:]) { $0[String($1.id)] = $1 }
        }
        archive = loaded

        // Before the guard below, which returns: a hall being placed is owed a
        // mirror whether or not this device syncs to iCloud.
        observeVenuePlacings()

        guard iCloudSyncEnabled, let cloud else { return }
        // Whatever another device wrote while this one was closed is merged
        // before the first screen reads anything.
        if let remote = cloud.load() {
            archive = archive.merging(remote)
        }
        observeCloudChanges()
        cloud.pull()
    }

    deinit {
        cloudChanges?.cancel()
        venuePlacings?.cancel()
        pendingMirror?.cancel()
        pendingSave?.cancel()
    }

    // MARK: - Reading

    var library: [Event] { archive.libraryEvents }

    var recentSearches: [String] { archive.recentSearches.value }

    var lastRefreshed: Date? { archive.lastRefreshed }

    /// The Eventernote account the reader imports from, if they have named one.
    var eventernoteHandle: String? { archive.eventernoteAccount?.value }

    /// How the linked account presents itself, as of the last page read from it.
    var eventernoteProfile: LinkedProfile? {
        // Guarded on the handle: an unlink leaves nothing to caption, and a
        // profile merged in beside a handle this device does not hold would
        // name an account the reader is not linked to.
        isLinked ? archive.eventernoteProfile : nil
    }

    /// Whether an account has been named. ``refresh()`` needs one — it is the
    /// list being refreshed from.
    var isLinked: Bool { eventernoteHandle != nil }

    func tracking(for event: Event) -> Tracking {
        archive.tracking[event.id]?.value ?? Tracking()
    }

    func status(for event: Event) -> TrackingStatus {
        TrackingStatus(tracking(for: event))
    }

    func isInLibrary(_ event: Event) -> Bool { archive.isInLibrary(event.id) }

    func isFavorite(_ event: Event) -> Bool { archive.isFavorite(event.id) }

    /// Whether emptying the library would still take anything.
    ///
    /// The library and the favorites are not the whole of it: a note, a ticket
    /// status or an attendance outlives the event it was written on, so this
    /// stays true while any of that is still held.
    var hasRecordsToDelete: Bool {
        !library.isEmpty
            || !favoriteEvents.isEmpty
            || archive.tracking.contains { !$0.value.value.isEmpty }
    }

    /// The freshest copy of an event this app holds, wherever it came from.
    func event(id: Event.ID) -> Event? {
        archive.events[id] ?? seen[id]
    }

    // MARK: - Writing

    func setTracking(_ tracking: Tracking, for event: Event) {
        archive.tracking[event.id] = Stamped(tracking)
        keep(event)
        persist()
    }

    func toggleFavorite(_ event: Event) {
        archive.favorites[event.id] = Stamped(!isFavorite(event))
        keep(event)
        persist()
    }

    /// Copying an event found in search into the library is always explicit: an
    /// import never does it silently. Taking one back out is explicit too, and
    /// answers only for this device and the reader's other ones — an event the
    /// linked account still lists is imported again on the next refresh.
    func toggleLibraryMembership(_ event: Event) {
        let wasIn = isInLibrary(event)
        archive.membership[event.id] = Stamped(!wasIn)
        if wasIn {
            if archive.tracking[event.id]?.value.isEmpty ?? true { archive.tracking[event.id] = nil }
        } else {
            keep(event)
            if archive.tracking[event.id] == nil {
                archive.tracking[event.id] = Stamped(Tracking(interest: .interested))
            }
        }
        persist()
    }

    /// Takes events out of the library in one go.
    ///
    /// Each one is tombstoned rather than dropped, exactly as a single removal
    /// is: the other device has to be told a removal happened, or the next merge
    /// would hand all of them straight back. The tombstone answers for the
    /// reader's devices and not for Eventernote — an event still on the linked
    /// account is imported again by the next refresh.
    ///
    /// Favorites are left alone. Hearting an event says "keep this in front of
    /// me", which is a separate answer from whether it is in the library.
    func remove(_ events: some Sequence<Event>) {
        let now = Date.now
        for event in events { tombstone(event.id, at: now) }
        persist()
    }

    /// Empties the library, and with it the favorites and everything the reader
    /// wrote on top of the events.
    ///
    /// Favorites go too here, unlike a removal of some events: a reader who
    /// asked for every event to go should not be left looking at a Favorites
    /// card that still lists a few. Tracking goes for the same reason, and it is
    /// the one place it does: a single removal keeps the note typed on an event
    /// so re-adding it brings the note back, but there is nothing to come back
    /// to once the reader has asked for all of it to go — and an import that
    /// restores the events would otherwise restore them wearing interest and
    /// ticket badges the reader thought they had just deleted.
    ///
    /// Each record is emptied rather than dropped, for the same reason a removal
    /// is a tombstone: a dropped key would let the next merge hand the other
    /// device's copy of the note straight back. An empty record is pruned once
    /// it has settled, exactly as a tombstone is.
    func removeAllEvents() {
        let now = Date.now
        for event in library { tombstone(event.id, at: now) }
        for id in archive.favorites.filter(\.value.value).keys {
            archive.favorites[id] = Stamped(false, at: now)
        }
        for (id, record) in archive.tracking where !record.value.isEmpty {
            archive.tracking[id] = Stamped(Tracking(), at: now)
        }
        persist()
    }

    /// Marks one event as removed. A note the reader typed outlives its event,
    /// so that re-adding it later brings the note back; an empty record does not.
    private func tombstone(_ id: Event.ID, at now: Date) {
        archive.membership[id] = Stamped(false, at: now)
        if archive.tracking[id]?.value.isEmpty ?? true {
            archive.tracking[id] = nil
        }
    }

    /// Holds on to what a search turned up, without adding any of it.
    func remember(_ events: [Event]) {
        for event in events where archive.events[event.id] == nil {
            seen[event.id] = event
        }
    }

    func remember(search term: String) {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        var recents = archive.recentSearches.value
        recents.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        recents.insert(term, at: 0)
        archive.recentSearches = Stamped(Array(recents.prefix(8)))
        persist()
    }

    func clearRecentSearches() {
        archive.recentSearches = Stamped([])
        persist()
    }

    /// Moves an event out of the transient search results and into the archive,
    /// which is what makes it worth saving and syncing.
    private func keep(_ event: Event) {
        let known = archive.events[event.id]
        let kept = known.map { $0.isDetailed ? $0.merging(event) : event.merging($0) } ?? event
        archive.events[event.id] = kept
        // Also left in `seen`, so a sheet still open keeps resolving if the
        // reader un-favorites it and pruning drops it from the archive.
        seen[event.id] = kept
    }

    /// Folds a freshly imported copy of an event back in, wherever it is held.
    private func apply(_ imported: Event) {
        if archive.events[imported.id] != nil {
            archive.events[imported.id] = imported
        } else {
            seen[imported.id] = imported
        }
    }

    // MARK: - Importing

    /// Imports one event's own page: the times, billing and head count a search
    /// row does not carry. Returns the event unchanged if Eventernote cannot be
    /// reached, so the sheet still shows what the row already knew.
    @discardableResult
    func loadDetail(for event: Event) async -> Event {
        guard let imported = try? await client.detail(for: event) else { return event }
        apply(imported)
        persist()
        return imported
    }

    /// Brings the library up to date — the one thing this screen asks for.
    ///
    /// It takes two passes, in this order: the linked account's own list first,
    /// so whatever it adds is in the library, and then each event's own page for
    /// the times, billing and head count a listing row never carries.
    ///
    /// A linked account is required. Without one there is no list to read, and
    /// the second pass alone is not what the reader is asking for when they tap
    /// Refresh; an event they added from Search still fills its own page in when
    /// they open it, through ``loadDetail(for:)``.
    ///
    /// Only imported fields are replaced. On failure the previous snapshot and
    /// its timestamp are kept: the app reports when it last *succeeded*, never
    /// that what it holds is current.
    func refresh() async {
        guard !isRefreshing, eventernoteHandle != nil else { return }
        isRefreshing = true
        refreshFailure = nil
        importSummary = nil
        defer {
            isRefreshing = false
            refreshStage = nil
        }

        let followed = await refreshAccount()

        // A history that failed still leaves events worth re-reading, so the
        // second pass runs either way and the first failure is the one reported.
        var landed = await importHistory()
        if await reimportDetails() { landed = true }

        // The history pass owns the summary, but it only writes one when it read
        // something. Follows adopted beside a history that reached nothing still
        // have something to report, so they are folded in either way.
        if followed > 0 {
            landed = true
            var summary = importSummary ?? ImportSummary(read: 0, added: 0, filled: 0)
            summary.followed = followed
            importSummary = summary
        }

        // The timestamp moves only when something actually arrived, so a run
        // that reached nothing cannot pass itself off as a successful refresh.
        guard landed else { return }
        archive.lastRefreshed = .now
        persist()
    }

    /// Re-reads the linked account's own page: the name and picture the Me
    /// screen captions it with, and the performers the account lists as
    /// favourites.
    ///
    /// One request, against a history that takes several — and it is what fills
    /// the name and picture in for an account linked before the app kept them,
    /// without asking the reader to link it again. A page that will not load
    /// leaves what is already held and is not reported: a refresh is about the
    /// library, and failing it over a portrait would be the wrong thing to tell
    /// the reader.
    ///
    /// Returns how many performers this pass newly followed.
    @discardableResult
    private func refreshAccount() async -> Int {
        guard let handle = eventernoteHandle,
              let read = try? await client.profile(forUser: handle)
        else { return 0 }

        let profile = LinkedProfile(name: read.name, avatarURL: read.avatarURL)
        let changedProfile = profile != archive.eventernoteProfile
        if changedProfile { archive.eventernoteProfile = profile }

        let follows = adoptFollows(read.favoritePerformers)
        if changedProfile || follows.changed { persist() }
        return follows.added
    }

    /// Follows the performers the linked account has favourited on Eventernote.
    ///
    /// The two lists stay distinct — the account's favourites are Eventernote's
    /// and this app only ever reads them; following is the reader's own record,
    /// kept here. What this does is bring the second in line with the first:
    ///
    /// - The favourites are taken as they stand. Somebody unfollowed here comes
    ///   back if the account still favourites them, because the account is what
    ///   the reader is asking to be followed when they tap Refresh — and it is
    ///   the only way back for somebody they took out and then wanted again.
    ///   Unfollowing for good means unfavouriting them on the site too.
    /// - An import still only ever adds. A performer dropped from the
    ///   favourites on the site is not unfollowed here: that would also reach
    ///   everyone the reader followed in Eventrail alone, since the site never
    ///   lists those.
    ///
    /// The favourites block prints no kana reading, so a profile already held —
    /// which came from performer search and carries one — is left alone rather
    /// than overwritten with the thinner copy.
    ///
    /// Returns how many this pass followed, and whether anything at all
    /// changed — naming somebody the archive was already following but could not
    /// name is a write with nothing to announce.
    private func adoptFollows(
        _ performers: [PerformerProfile]
    ) -> (added: Int, changed: Bool) {
        guard !performers.isEmpty else { return (0, false) }
        let now = Date.now
        var follows = archive.follows ?? [:]
        var profiles = archive.followedPerformers ?? [:]
        var added = 0
        var changed = false

        for performer in performers {
            let key = String(performer.id)
            // Anything but an existing `true` is written: a missing record is
            // the first read of them, and a tombstone is undone by the same act
            // that would have to undo it — asking Eventernote again.
            if follows[key]?.value != true {
                follows[key] = Stamped(true, at: now)
                added += 1
                changed = true
            }
            guard profiles[key] == nil else { continue }
            // Also reaches a follow recorded before the app kept profiles, which
            // until now had an actor id and no way to name it.
            profiles[key] = performer
            changed = true
        }

        guard changed else { return (0, false) }
        archive.follows = follows
        archive.followedPerformers = profiles
        return (added, true)
    }

    /// The events whose own page is worth asking for.
    ///
    /// An upcoming event can still change — Eventernote announces times and
    /// venues late — so those are always re-read. A past event that has already
    /// been read is settled, and re-reading nine hundred of them on every
    /// refresh would be a great many requests for facts that cannot move.
    /// One never read is fetched whenever it falls, which is what fills in a
    /// freshly imported history; a page that fails stays undetailed and is
    /// picked up again by the next refresh.
    private var needsReading: [Event] {
        library.filter { $0.isUpcoming || !$0.isDetailed }
    }

    /// Reads those pages a few at a time, reporting whether the pass got
    /// through at all. An event whose page failed keeps the copy already held.
    private func reimportDetails() async -> Bool {
        let events = needsReading
        guard !events.isEmpty else { return true }
        refreshStage = .reimporting(read: 0, total: events.count)

        let client = client
        let inFlight = 4
        var read = 0
        var landed = 0

        await withTaskGroup(of: Event?.self) { group in
            var next = events.startIndex
            func addTask() {
                guard next < events.endIndex else { return }
                let event = events[next]
                next = events.index(after: next)
                group.addTask { try? await client.detail(for: event) }
            }

            for _ in 0 ..< min(inFlight, events.count) { addTask() }
            for await result in group {
                read += 1
                if let result {
                    apply(result)
                    landed += 1
                }
                refreshStage = .reimporting(read: read, total: events.count)
                addTask()
            }
        }

        guard landed > 0 else {
            if refreshFailure == nil {
                refreshFailure = String(localized: "Could not reach Eventernote. Showing the last import.")
            }
            return false
        }
        return true
    }

    // MARK: - The linked Eventernote account

    /// Confirms a handle names a real account, without recording anything.
    ///
    /// The reader sees who they are about to link before the app commits to it —
    /// handles are short and easy to mistype, and a wrong one would otherwise
    /// import a stranger's history into their library.
    func lookUpAccount(_ typed: String) async throws -> EventernoteProfile {
        guard let handle = EventernoteClient.Account.normalized(typed) else {
            throw EventernoteClient.Failure.unreadable
        }
        return try await client.profile(forUser: handle)
    }

    func link(_ profile: EventernoteProfile) {
        // Re-linking the same account is not a reason to import it again, but the
        // reader has just looked at a fresh copy of their page — it is the newest
        // the app will have until the next refresh, so it is kept either way.
        let isSameAccount = profile.handle == eventernoteHandle
        archive.eventernoteProfile = LinkedProfile(name: profile.name, avatarURL: profile.avatarURL)
        guard !isSameAccount else { return persist() }

        archive.eventernoteAccount = Stamped(profile.handle)
        archive.lastImported = nil
        importSummary = nil
        refreshFailure = nil
        persist()
    }

    /// Forgets the account. What it already imported stays: those events are in
    /// the library now, and unlinking is about where the app looks next, not
    /// about undoing what the reader has collected.
    func unlinkAccount() {
        guard eventernoteHandle != nil else { return }
        // A nil inside the stamp rather than a dropped record, so the unlink
        // reaches the other device instead of being merged away.
        archive.eventernoteAccount = Stamped(nil)
        archive.eventernoteProfile = nil
        archive.lastImported = nil
        importSummary = nil
        refreshFailure = nil
        persist()
    }

    /// Imports every event the linked account is listed as attending.
    ///
    /// Three rules keep this from talking over the reader:
    ///
    /// - An event they removed is imported again, because the account still
    ///   lists it and the account is what they asked to be read. What a removal
    ///   settles is their own devices, through the tombstone a merge honours;
    ///   nothing here has ever claimed it settles Eventernote too.
    /// - The first import after linking fills in the tracking they have left
    ///   blank; every import after that only fills in events it has just added.
    ///   `Attendance.unrecorded` cannot be told apart from an answer the reader
    ///   gave, so a later import that re-asserted it would quietly undo them
    ///   marking a registered event as one they did not go to.
    /// - A page that fails does not discard the pages that worked. The import
    ///   adopts what it read and says it stopped short.
    ///
    /// Notes and ticket status are never written by an import at all.
    ///
    /// Reports whether anything was adopted, so ``refresh()`` knows whether the
    /// pass is worth stamping.
    private func importHistory() async -> Bool {
        guard let handle = eventernoteHandle else { return false }
        // Read before the import stamps itself, so the catch-up run knows it is
        // the catch-up run.
        let isCatchingUp = archive.lastImported == nil
        refreshStage = .readingHistory(read: 0, total: 0)

        var imported: [Event] = []
        var page = 1

        while true {
            let read: EventernotePage<Event>
            do {
                read = try await client.events(forUser: handle, page: page)
            } catch {
                refreshFailure = page == 1
                    ? String(localized: "Could not reach Eventernote. Nothing was imported.")
                    : String(localized: "Eventernote stopped answering partway through. What did arrive was imported.")
                break
            }
            imported += read.items
            refreshStage = .readingHistory(read: imported.count, total: max(read.total, imported.count))
            // An empty page ends the run even if the site's own count disagrees,
            // so a miscounted total cannot spin this forever.
            guard read.hasMore, !read.items.isEmpty else { break }
            page += 1
        }

        guard !imported.isEmpty else { return false }
        // The site lists the odd event twice, on two adjacent rows of the same
        // page. Adopting it twice is harmless, but counting it twice would
        // overstate what arrived.
        var seen: Set<Event.ID> = []
        let distinct = imported.filter { seen.insert($0.id).inserted }

        let counts = adopt(distinct, fillingBlanks: isCatchingUp)
        archive.lastImported = .now
        importSummary = ImportSummary(read: distinct.count, added: counts.added,
                                      filled: counts.filled)
        return true
    }

    /// Folds an imported history into the archive under the rules above.
    ///
    /// `fillingBlanks` reaches events already in the library — the ones saved
    /// from Search before the account was linked. Without it only the events
    /// this import adds are ruled on, and everything the reader has already
    /// answered, or deliberately left blank, stays as they left it.
    private func adopt(_ imported: [Event], fillingBlanks: Bool) -> (added: Int, filled: Int) {
        let now = Date.now
        var added = 0
        var filled = 0

        for event in imported {
            // A removal is not permanent. The account's history is what the
            // reader is asking for when they tap Refresh, so an event they took
            // out comes back if Eventernote still lists it — the same rule the
            // favourites follow. Taking one out for good means taking it off the
            // account, and an event that was never on it stays gone.
            let isNew = !archive.isInLibrary(event.id)
            if isNew {
                archive.membership[event.id] = Stamped(true, at: now)
                added += 1
            }
            keep(event)

            guard isNew || fillingBlanks else { continue }
            let recorded = archive.tracking[event.id]?.value ?? Tracking()
            let completed = completing(recorded, for: event)
            // Only a real change is stamped: rewriting an unchanged record would
            // make this device win a merge it has nothing new to say in.
            if completed != recorded {
                archive.tracking[event.id] = Stamped(completed, at: now)
                filled += 1
            }
        }
        return (added, filled)
    }

    /// Fills the one field the account listing actually evidences, and only when
    /// the reader has not answered it themselves.
    private func completing(_ tracking: Tracking, for event: Event) -> Tracking {
        var completed = tracking
        if event.isUpcoming {
            if completed.interest == .none { completed.interest = .planning }
        } else if completed.attendance == .unrecorded {
            completed.attendance = .attended
        }
        return completed
    }

    // MARK: - Syncing

    /// Merges whatever iCloud holds and pushes the result back, so the two
    /// copies agree in both directions rather than one overwriting the other.
    func syncNow() async {
        // A ticket bought on the other device is a calendar entry owed on this
        // one, so the mirror runs whether or not iCloud is in the picture.
        defer { Task { await mirrorCalendar() } }
        guard iCloudSyncEnabled, let cloud else { return }
        guard cloud.isConfigured else {
            syncStatus = .notConfigured
            return
        }
        guard cloud.isAvailable else {
            syncStatus = .signedOut
            return
        }
        if let remote = cloud.load() {
            archive = archive.merging(remote)
        }
        archive = archive.pruned()
        let outcome = cloud.save(archive)
        syncStatus = outcome
        if outcome == .synced { lastSynced = .now }
        file?.save(archive)
        if cloudChanges == nil { observeCloudChanges() }
    }

    /// Flushes a pending write immediately.
    ///
    /// Edits are written after a short pause; the app leaving the foreground
    /// cuts that pause short, so the last one is committed here rather than lost.
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        archive = archive.pruned()
        file?.save(archive)
        guard iCloudSyncEnabled, let cloud, cloud.isConfigured, cloud.isAvailable else { return }
        let outcome = cloud.save(archive)
        syncStatus = outcome
        if outcome == .synced { lastSynced = .now }
    }

    /// How much of iCloud's quota the library takes up, 0...1.
    var cloudUsage: Double {
        cloud?.usage(of: archive) ?? 0
    }

    /// The events a calendar entry is owed: everything in the library, upcoming
    /// and past alike.
    ///
    /// Adding an event to the library is already the reader saying it is theirs,
    /// and that is the whole of the rule — the mirror does not go on to second-
    /// guess it by tracking field. An earlier cut on the ticket field quietly
    /// left every past event out, because nothing back-fills a ticket for a
    /// night already over.
    var calendarEvents: [Event] { library }

    /// Brings the calendar into line with the library, or clears it out when
    /// the reader has turned the mirror off.
    ///
    /// Safe to call after any edit: with the mirror off and nothing ever
    /// written, it does nothing at all — in particular it never asks for
    /// calendar permission on its own.
    func mirrorCalendar() async {
        guard let calendar else { return }
        guard calendarSyncEnabled else {
            await calendar.stop()
            calendarStatus = nil
            return
        }
        calendarStatus = await calendar.mirror(calendarEvents)
    }

    /// Every event whose hall is worth asking about: the library and the
    /// favorites, which need not be in it — an event favorited out of Search
    /// draws the same map on its own sheet.
    private var placeableEvents: [Event] {
        var seen: Set<Event.ID> = []
        return (library + favoriteEvents).filter { seen.insert($0.id).inserted }
    }

    /// Whether there is any hall to ask about. A library of events the site
    /// has not booked a venue for yet is nothing to send Maps after.
    var hasVenuesToPlace: Bool {
        placeableEvents.contains { !$0.venue.isEmpty || $0.publishedAddress != nil }
    }

    /// Asks Maps again about every hall the reader holds, and then writes what
    /// comes back into their calendar.
    ///
    /// The one place anything looks up halls in bulk — see ``VenuePlaces`` for
    /// why that is otherwise avoided, and why this takes minutes rather than
    /// seconds. The mirror afterwards is the point as much as the lookup is:
    /// entries written while a hall was still unplaced carry its name and no
    /// map, and nothing else goes back to correct them.
    func refreshVenues() async {
        guard let venues, !isRefreshingVenues else { return }
        // Nothing counted yet: how many halls there are is the refresh's own
        // answer, once it has sorted the events into the halls they share.
        venueStatus = .asking(done: 0, of: 0)
        venueStatus = await venues.refresh(placeableEvents) { progress in
            self.venueStatus = progress
        }
        await mirrorCalendar()
    }

    /// A hall has been placed that was not placed before, so whatever was
    /// written into the calendar about it is now out of date.
    ///
    /// The mirror only ever writes what ``VenuePlaces`` already knows — it
    /// never goes looking for a hall itself — so an event at a hall nothing
    /// had looked up became an entry with the hall's name and no map. Opening
    /// that event is what finally asks Maps, and this is what then goes back
    /// and corrects the entry. Without it the reader would be left with an
    /// entry Calendar cannot draw a map for or work out a journey to, and
    /// nothing short of an edit to the library would ever mend it.
    private func observeVenuePlacings() {
        guard let venues, calendar != nil else { return }
        venuePlacings = Task { [weak self] in
            for await _ in venues.placings {
                self?.mirrorSoon()
            }
        }
    }

    /// Mirrors once the halls stop arriving.
    ///
    /// Coalesced the way ``persist()`` coalesces a burst of edits, and for the
    /// same reason: a reader flicking through four events in a row places four
    /// halls, and that is one mirror's worth of work rather than four. The
    /// wait is long enough to cover reading a screen and short enough that the
    /// calendar is right by the time they look at it.
    private func mirrorSoon() {
        guard calendarSyncEnabled else { return }
        pendingMirror?.cancel()
        pendingMirror = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.mirrorCalendar()
        }
    }

    /// Another device wrote. Merge rather than adopt: this device may have
    /// edits of its own that have not been pushed yet.
    private func observeCloudChanges() {
        cloudChanges = Task { [weak self] in
            let changes = NotificationCenter.default.notifications(
                named: NSUbiquitousKeyValueStore.didChangeExternallyNotification
            )
            for await _ in changes {
                guard let self, self.iCloudSyncEnabled, let remote = self.cloud?.load() else { continue }
                self.archive = self.archive.merging(remote)
                self.lastSynced = .now
                self.syncStatus = .synced
                self.file?.save(self.archive)
            }
        }
    }

    // MARK: - Persisting

    /// Coalesces the writes a burst of edits produces — typing in a note field
    /// should not touch the disk, or iCloud, on every keystroke.
    private func persist() {
        pendingSave?.cancel()
        // Pruning here, not only on merge: an event the reader removed must stop
        // being uploaded, not linger in iCloud until some other device syncs.
        archive = archive.pruned()
        revision += 1
        let archive = archive
        let file = file
        let cloud = iCloudSyncEnabled ? cloud : nil
        guard file != nil || cloud != nil else { return }

        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let outcome = await Task.detached(priority: .utility) { () -> CloudSync.Outcome? in
                file?.save(archive)
                return cloud?.save(archive)
            }.value
            guard !Task.isCancelled, let self else { return }
            if let outcome {
                self.syncStatus = outcome
                if outcome == .synced { self.lastSynced = .now }
            }
            // The calendar follows the same pause as the disk write: a ticket
            // toggled twice while deciding should reach EventKit once.
            await self.mirrorCalendar()
        }
    }

    // MARK: - Grouping

    func events(matching filter: LibraryFilter) -> [Event] {
        events(in: library, matching: filter)
    }

    /// The same half of a list the caller has already chosen — the favorites,
    /// say, rather than the whole library.
    func events(in pool: some Sequence<Event>, matching filter: LibraryFilter) -> [Event] {
        switch filter {
        case .upcoming:
            pool.filter(\.isUpcoming).sorted { $0.sortDate < $1.sortDate }
        case .past:
            pool.filter { !$0.isUpcoming }.sorted { $0.sortDate > $1.sortDate }
        }
    }

    func groups(filter: LibraryFilter, grouping: Grouping) -> [EventGroup] {
        groups(of: library, filter: filter, grouping: grouping)
    }

    /// The same breakdown over a chosen list, for the screens that hold one
    /// that is not the library.
    func groups(of pool: some Sequence<Event>, filter: LibraryFilter,
                grouping: Grouping) -> [EventGroup] {
        let events = events(in: pool, matching: filter)
        switch grouping {
        case .date:
            // `events` is already date-ordered, so first appearance sets section order.
            var order: [String] = []
            var buckets: [String: [Event]] = [:]
            for event in events {
                let key = event.monthGroupLabel
                if buckets[key] == nil { order.append(key) }
                buckets[key, default: []].append(event)
            }
            return order.map { EventGroup(id: $0, label: $0, events: buckets[$0] ?? []) }
        case .artist:
            var buckets: [String: [Event]] = [:]
            for event in events { buckets[event.artist, default: []].append(event) }
            return buckets
                .map { EventGroup(id: $0.key, label: $0.key, events: $0.value) }
                // Busiest artist first, then alphabetically so the order is stable.
                .sorted { ($0.events.count, $1.label) > ($1.events.count, $0.label) }
        }
    }

    // MARK: - Backups

    /// Everything the reader owns, as one file they can keep outside the app.
    ///
    /// Cheap to ask for — the archive is a value; writing it out is the
    /// expensive part, and that is the caller's to do.
    var backup: LibraryBackup { LibraryBackup(archive: archive) }

    /// Counts every write the reader has made this launch.
    ///
    /// A screen holding something derived from the whole archive — the export
    /// file, which has to exist before the share sheet can preview it — watches
    /// this rather than trying to spot the change itself. Counting records
    /// would not do: a removal leaves a tombstone behind and an emptied note
    /// keeps its key, so the archive can change without changing size.
    private(set) var revision = 0

    /// What a restore put back, in the two numbers worth stating: what was
    /// missing and came back, and what was already here.
    ///
    /// Counted from the library on either side of the merge rather than from
    /// the file, so it reports what actually changed instead of what the backup
    /// happened to contain.
    struct RestoreSummary: Hashable {
        var events: Int
        var follows: Int
        /// Notes, interest, ticket status and attendance brought back.
        var records: Int

        var isEmpty: Bool { events == 0 && follows == 0 && records == 0 }
    }

    /// Reads a backup the reader picked and folds it in.
    ///
    /// Additive by design — see ``LibraryArchive/restoring(_:)``. Restoring a
    /// file brings back what this device no longer has; it never takes away
    /// what the file was written before.
    @discardableResult
    func restore(from url: URL) throws -> RestoreSummary {
        let backup = try LibraryBackup.read(at: url)
        let before = archive
        archive = archive.restoring(backup.archive)
        persist()
        let held = Self.held(in: archive)
        let was = Self.held(in: before)
        return RestoreSummary(events: held.events - was.events,
                              follows: held.follows - was.follows,
                              records: held.records - was.records)
    }

    /// How much of each kind an archive holds, for either side of a restore.
    private static func held(in archive: LibraryArchive) -> RestoreSummary {
        RestoreSummary(
            events: archive.membership.values.count { $0.value },
            follows: (archive.follows ?? [:]).values.count { $0.value },
            records: archive.tracking.values.count { !$0.value.isEmpty }
        )
    }

    // MARK: - Favorites

    /// Everything the reader has hearted, upcoming first and then most recent
    /// past — the same ordering the library uses.
    ///
    /// A favorite can point at an event found in search and never added to the
    /// library, so this resolves through ``event(id:)`` rather than ``library``.
    var favoriteEvents: [Event] {
        let events = archive.favorites.compactMap { $0.value.value ? event(id: $0.key) : nil }
        let upcoming = events.filter(\.isUpcoming).sorted { $0.sortDate < $1.sortDate }
        let past = events.filter { !$0.isUpcoming }.sorted { $0.sortDate > $1.sortDate }
        return upcoming + past
    }

    // MARK: - Followed performers

    func isFollowing(_ performer: PerformerProfile) -> Bool {
        archive.isFollowing(performer.id)
    }

    /// Everyone the reader follows, by name.
    ///
    /// Ordered rather than merely listed: this is a settled list the reader
    /// returns to, and a dictionary's order would reshuffle the Me card and the
    /// Following filters between launches.
    var followedPerformers: [PerformerProfile] { archive.followedProfiles }

    /// Follows a performer, or stops following them.
    ///
    /// The reader's own list, kept beside their library. The favourite list
    /// their Eventernote account holds is theirs to edit on Eventernote — this
    /// app only ever reads from there.
    ///
    /// Who they are is recorded alongside the decision: the Following tab has
    /// to name them and ask the site for their dates, and neither is possible
    /// from an actor id alone.
    func toggleFollow(_ performer: PerformerProfile) {
        let following = !isFollowing(performer)
        var follows = archive.follows ?? [:]
        follows[String(performer.id)] = Stamped(following)
        archive.follows = follows

        var profiles = archive.followedPerformers ?? [:]
        // Unfollowing leaves a tombstone but no profile — `pruned()` drops it,
        // which is what keeps the archive from carrying people it no longer
        // follows all the way to iCloud.
        profiles[String(performer.id)] = following ? performer : nil
        archive.followedPerformers = profiles

        persist()
    }

    /// Stops following someone from a list that shows them, where the profile
    /// is the only handle on who they are.
    func unfollow(_ performer: PerformerProfile) {
        guard isFollowing(performer) else { return }
        toggleFollow(performer)
    }

    /// How many events in the library this performer is billed on and the
    /// reader has marked attended.
    ///
    /// Counted over the library rather than over the appearances a performer's
    /// page has read so far, so the number is the whole of it however little of
    /// that listing has been paged in.
    func attendedCount(billing name: String) -> Int {
        attendedEvents.filter { event in
            event.performers.contains { $0.name == name }
        }.count
    }

    // MARK: - Profile statistics

    private var attendedEvents: [Event] {
        library.filter { tracking(for: $0).attendance == .attended }
    }

    var eventsThisYear: Int {
        let year = Calendar.current.component(.year, from: .now)
        return library.filter { Calendar.current.component(.year, from: $0.date) == year }.count
    }

    var venuesVisited: Int {
        Set(attendedEvents.map(\.venue)).count
    }

    var performersSeen: Int {
        Set(attendedEvents.flatMap { $0.performers.map(\.name) }).count
    }
}
