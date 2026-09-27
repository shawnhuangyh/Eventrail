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

    /// This half of a list, in the order this half is read in: what is coming
    /// runs towards the reader, what has happened runs away from them.
    ///
    /// Lives on the filter rather than on the store because it is a fact about
    /// the two halves rather than about the library — a performer's listing is
    /// split the same way, and used to be split by a second copy of this.
    func rows(of events: some Sequence<Event>) -> [Event] {
        switch self {
        case .upcoming:
            events.filter(\.isUpcoming).sorted { $0.sortDate < $1.sortDate }
        case .past:
            events.filter { !$0.isUpcoming }.sorted { $0.sortDate > $1.sortDate }
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

    /// A date-ordered run of events broken into the months it spans.
    ///
    /// The caller has already put the events in the order the reader will read
    /// them, so first appearance sets section order — which is what keeps the
    /// past running backwards and the future forwards without this having to
    /// know which it was handed.
    ///
    /// The library groups its months with it and so does the Following tab,
    /// which used to hold a second copy of the same loop, comment included.
    static func byMonth(_ events: [Event]) -> [EventGroup] {
        var order: [String] = []
        var buckets: [String: [Event]] = [:]
        for event in events {
            let key = event.monthGroupLabel
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(event)
        }
        return order.map { EventGroup(id: $0, label: $0, events: buckets[$0] ?? []) }
    }
}

/// The reader's library, and every write to it.
///
/// Imported facts and the reader's own records are kept strictly apart: an
/// import replaces ``LibraryArchive/events`` and never reads or writes tracking,
/// membership or favorites. Every change is mirrored to ``LibraryFile`` so it
/// survives the app closing, and — when the reader has it switched on — sent
/// through ``CloudSync`` so their other devices see it.
@Observable
@MainActor
final class EventStore: CloudSyncHost {
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

    /// What one import changed.
    ///
    /// Read and added are different numbers because the account lists events
    /// the library already holds: an import that read ninety and added none is
    /// a library already in step rather than an import that failed.
    ///
    /// A summary and a ``refreshFailure`` can both be set: a history that read
    /// six pages of nine still adopted those six.
    struct ImportSummary: Hashable {
        var read: Int
        var added: Int
        /// Performers newly followed from the account's own favourites, which
        /// come off the member page rather than out of the history.
        var followed: Int = 0
    }

    /// Whether this device mirrors the library to iCloud. A per-device choice,
    /// so it deliberately does not sync: turning sync off on a phone should not
    /// turn it off on the iPad.
    ///
    /// Off until the reader turns it on, like ``calendarSyncEnabled``. Copying
    /// what they have written into their iCloud is theirs to say yes to — the
    /// Welcome screen asks, and Settings carries the same row — and a switch
    /// found already on is not an answer anybody gave.
    var iCloudSyncEnabled: Bool {
        didSet {
            guard iCloudSyncEnabled != oldValue else { return }
            UserDefaults.standard.set(iCloudSyncEnabled, forKey: Self.syncPreferenceKey)
            if iCloudSyncEnabled {
                Task { await syncNow() }
            } else {
                syncStatus = nil
                Task { await cloud?.stop() }
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

    /// How many library files this build found and could not read. Each was
    /// set aside rather than written over — see ``LibraryFile/load()`` — and
    /// Settings says so, since the library on screen is missing what they hold.
    private(set) var unreadableLibraryFiles = 0

    /// Whether the library file on disk could not be read this launch and is
    /// still where it was — see ``LibraryFile/Contents/isBlocked``. Nothing is
    /// written to it meanwhile; each save tries the read again first
    /// (``fileToWrite()``), and Settings says so while it lasts.
    private(set) var libraryFileIsBlocked = false

    /// Set-aside files folded back in at launch, deleted once the library
    /// holding them is on disk — see ``LibraryFile/discard(_:)``.
    private var recoveredCopies: [URL] = []

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
    /// Which event pages this device has already read, so a refresh does not
    /// ask for them all again — see ``PageReads``.
    private let pageReads: PageReads?
    private let client: EventernoteClient
    private var pendingSave: Task<Void, Never>?
    private var venuePlacings: Task<Void, Never>?
    private var pendingMirror: Task<Void, Never>?
    /// The halls an import brought in, being placed behind it.
    private var venuePlacement: Task<Void, Never>?
    /// Events the reader has just added by hand, waiting for their hall to be
    /// looked up — see ``placeAdded(_:)``.
    private var arrivals: [Event.ID] = []
    private var arrivalPlacement: Task<Void, Never>?
    /// The page read going on now for each event, so a pull that lands while
    /// the sheet's own read is running — or a return to the foreground in the
    /// middle of one — waits for it rather than asking for the page again.
    private var detailReads: [Event.ID: Task<PageRead, Never>] = [:]

    /// The default store reads the reader's own library from disk and, if they
    /// have sync on, merges whatever iCloud holds. Previews and the playground
    /// pass events in and leave `file` and `cloud` nil, so nothing they do is
    /// written or synced anywhere.
    init(
        file: LibraryFile? = .shared,
        cloud: CloudSync? = .shared,
        calendar: CalendarSync? = .shared,
        venues: VenuePlaces? = .shared,
        pageReads: PageReads? = .shared,
        client: EventernoteClient = .shared,
        library: [Event] = [],
        tracking: [Event.ID: Tracking] = [:],
        follows: [PerformerProfile] = []
    ) {
        self.file = file
        self.cloud = cloud
        self.calendar = calendar
        self.venues = venues
        self.pageReads = pageReads
        self.client = client

        // Off until the reader says otherwise, the same as the calendar. A
        // preview has no file and never syncs.
        iCloudSyncEnabled = file != nil
            && UserDefaults.standard.bool(forKey: Self.syncPreferenceKey)
        calendarSyncEnabled = calendar != nil
            && UserDefaults.standard.bool(forKey: Self.calendarPreferenceKey)
        preciseVenuesEnabled = venues?.usesOpenStreetMap ?? false

        let contents = file?.load()
        unreadableLibraryFiles = contents?.unreadable ?? 0
        libraryFileIsBlocked = contents?.isBlocked ?? false
        recoveredCopies = contents?.recoveredCopies ?? []
        var loaded = contents?.archive ?? LibraryArchive()
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

        // Before the merge below, which returns on a device that does not sync:
        // a hall being placed is owed a mirror whether or not this one does.
        observeVenuePlacings()

        // What another device wrote arrives once the engine has started.
        if iCloudSyncEnabled, cloud != nil {
            Task { await self.syncNow() }
        }

        // Written back rather than only held: what this corrects is a night
        // abroad imported before its hall was placed, and correcting it once a
        // launch would be correcting it forever.
        if retimeEvents() || contents?.recovered == true { persist() }
    }

    isolated deinit {
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

    /// The one badge a row wears, read from where the event stands.
    ///
    /// An event in the library that has already happened is one the reader
    /// went to — that is what putting it there means, and it is why there is
    /// no attendance to record. Still to come, the ticket is the only thing
    /// left that the library does not already say. An event nobody has kept is
    /// untracked however its date reads, so a past search result does not
    /// announce itself as attended.
    func status(for event: Event) -> TrackingStatus {
        let isKept = isInLibrary(event)
        if isKept, !event.isUpcoming { return .attended }
        if tracking(for: event).ticket == .purchased { return .ticketed }
        return isKept ? .planned : .untracked
    }

    func isInLibrary(_ event: Event) -> Bool { archive.isInLibrary(event.id) }

    func isFavorite(_ event: Event) -> Bool { archive.isFavorite(event.id) }

    /// Whether emptying the library would still take anything.
    ///
    /// The library and the favorites are not the whole of it: a note or a
    /// ticket status outlives the event it was written on, so this stays true
    /// while either is still held.
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
        // Written against the record as it stands, so that a merge can tell
        // which of the five answers this device actually changed — see
        // ``Stamped/edited(to:at:)``. A record this device has never held is
        // as old as a record can be: every answer in it is one the reader has
        // not given here, so the other device's copy of any of them outranks
        // it.
        let held = archive.tracking[event.id] ?? Stamped(Tracking(), at: .distantPast)
        archive.tracking[event.id] = held.edited(to: tracking)
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
            // Nothing to write down: being in the library is what says the
            // reader means to go, which is what a tracking record used to be
            // opened to say for it.
            keep(event)
            placeAdded(event)
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
    /// restores the events would otherwise restore them wearing ticket badges
    /// the reader thought they had just deleted.
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
        // Every Following date back to unread, on every device: written as a
        // record with no fingerprint rather than dropped, or the other
        // device's copy of each read would come straight back in the merge.
        for (id, record) in archive.followingReads ?? [:] where record.value.fingerprint != nil {
            archive.followingReads?[id] = Stamped(FollowingRead(fingerprint: nil, day: record.value.day),
                                                  at: now)
        }
        persist()
    }

    // MARK: - What the reader has looked at on Following and My Events

    /// Whether this copy of a Following row is one the reader has not seen —
    /// see ``FollowingRead``. My Events reads the same record for its
    /// upcoming rows, so a date read on one tab is read on the other.
    func isUnread(_ event: Event) -> Bool { archive.isUnread(event) }

    /// Why a Following row is unread — new, or changed since it was read —
    /// or nil where it is read.
    func unread(_ event: Event) -> FollowingUnread? { archive.unread(event) }

    /// Marks these rows read as the listing prints them now, or unread again.
    /// One write for the lot, however many there are — Select All then Mark
    /// is hundreds of them.
    func markRead(_ events: some Sequence<Event>, read: Bool) {
        let now = Date.now
        var reads = archive.followingReads ?? [:]
        var changed = false
        for event in events where archive.isUnread(event) == read {
            reads[event.id] = Stamped(
                FollowingRead(fingerprint: read ? event.listingFingerprint : nil, day: event.date),
                at: now)
            changed = true
        }
        guard changed else { return }
        archive.followingReads = reads
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

    /// Reads the next page of a listing once the reader has scrolled close
    /// enough to the end of the one in hand, and holds on to what it brings.
    ///
    /// Three screens page a listing of events this way — search results, a
    /// performer's page, and the screen behind its See All — and all three have
    /// to remember what arrives, or a row tapped after paging would open a
    /// sheet with nothing behind it. Written out at each of them, the remember
    /// was one edit away from being dropped at one and kept at the other two.
    func pageOn(_ feed: Feed<Event>, after event: Event) async {
        guard feed.isNearEnd(event) else { return }
        await feed.loadMore()
        remember(feed.items)
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
    ///
    /// Every read of an event's own page arrives here, so this is also where
    /// the read is written down — see ``isStale(_:)`` for what that decides.
    /// `asked` is when the page was asked for, so a read the cache was
    /// cleared under is not stamped fresh on its way in.
    private func apply(_ imported: Event, asked: Date) {
        pageReads?.record(imported.id, asked: asked)
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
        let asked = Date.now
        guard let imported = try? await client.detail(for: event) else { return event }
        apply(imported, asked: asked)
        persist()
        return imported
    }

    /// Whether an event's own page is worth reading again by itself — which is
    /// what an event's sheet asks as it opens.
    ///
    /// Stale once this device's last read of it is more than
    /// ``PageReads/freshness`` old, or when there is no read written down at
    /// all, which is every event imported before this build kept them. Only
    /// the app's own reading asks this: a refresh the reader asked for reads
    /// regardless.
    func isStale(_ event: Event) -> Bool {
        guard let pageReads else { return false }
        return !pageReads.isFresh(event.id)
    }

    /// How one read of an event's page ended, for the sheet that asked.
    enum PageRead {
        case updated
        case failed(String)
    }

    /// Reads one event's own page again for a sheet that is open on it.
    ///
    /// The copy already held stays whatever happens — the sheet goes on showing
    /// it, with the reason underneath.
    ///
    /// **The request runs as a task of its own, out of reach of the caller's
    /// cancellation.** A pull on the sheet runs inside `.refreshable`, and
    /// SwiftUI cancels that action when the screen under it changes while it
    /// is running — which this sheet does the moment a read starts, since its
    /// footnote says so. The cancellation reached the request, URLSession
    /// dropped it, and the pull ended in neither an answer nor an error: the
    /// reader saw nothing happen at all. ``FollowedDates`` reads the same way,
    /// for its own reasons, which is why its pull never went quiet. A read
    /// that outlives its sheet still lands in the library and is still
    /// reported, which is true either way.
    ///
    /// One read per event at a time: a second caller joins the one running and
    /// is told what it came to, the way a pull on Following joins
    /// ``FollowedDates``' read — two answers landing over each other would be
    /// two requests for one page and a race over which copy is kept.
    func reloadDetail(for event: Event) async -> PageRead {
        if let running = detailReads[event.id] { return await running.value }
        let client = client
        let task = Task { () -> PageRead in
            do {
                let asked = Date.now
                let imported = try await client.detail(for: event)
                apply(imported, asked: asked)
                persist()
                return .updated
            } catch {
                return .failed(error.localizedDescription)
            }
        }
        detailReads[event.id] = task
        let read = await task.value
        detailReads[event.id] = nil
        return read
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
    ///
    /// Answers whether it ran at all — a tap while one is already going, or
    /// with no account to read, is not a refresh worth a notice.
    @discardableResult
    func refresh() async -> Bool {
        guard !isRefreshing, eventernoteHandle != nil else { return false }
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
            var summary = importSummary ?? ImportSummary(read: 0, added: 0)
            summary.followed = followed
            importSummary = summary
        }

        // The timestamp moves only when something actually arrived, so a run
        // that reached nothing cannot pass itself off as a successful refresh.
        guard landed else { return true }
        archive.lastRefreshed = .now
        persist()
        placeArrivedVenues()
        return true
    }

    /// Sends the import's new halls off to Maps, and does not wait for them.
    ///
    /// Behind the import rather than inside it, for two reasons. The reader is
    /// watching a Refresh button, and a hall a second is not what they are
    /// waiting on — the events are already in their library, and the map under
    /// one of them is the only thing still missing. And an import that reached
    /// Eventernote has done what it said it would; a Maps run that fails
    /// afterwards is not a failed import and must not be reported as one.
    ///
    /// Only what has no answer yet, which is what makes it safe to do without
    /// being asked — see ``VenuePlaces/placeUnplaced(_:onProgress:)``. The
    /// second import of a library that has not moved asks Maps nothing, says
    /// nothing, and mirrors nothing.
    private func placeArrivedVenues() {
        venuePlacement?.cancel()
        venuePlacement = Task { [weak self] in
            guard let self, venues != nil, !isRefreshingVenues else { return }
            let outcome = await venues?.placeUnplaced(placeableEvents) { progress in
                self.venueStatus = progress
            }
            // Before the report and its early return: a run that placed
            // nothing new may still have settled which clock a hall abroad
            // keeps, and the events there are owed that.
            if retimeEvents() { persist() }
            // Nothing to ask about is nothing to report: a status here would
            // put "Placed 0 of 0 venues" under a Settings row that had done
            // no work, where nil correctly leaves it saying what it would do.
            guard let outcome, outcome != .refreshed(found: 0, of: 0) else {
                venueStatus = nil
                return
            }
            venueStatus = outcome
            // The one mirror the whole run gets, for the reason a refresh from
            // Settings mirrors once at the end rather than per hall.
            await mirrorCalendar()
        }
    }

    /// Finds the hall of an event the reader has just put in their library,
    /// without being asked and without holding anything up.
    ///
    /// An import places the halls it brings in — ``placeArrivedVenues()`` —
    /// and an event added by hand from Search was the one way into the library
    /// that placed nothing. It sat there unplaced: no dot on the Passport's
    /// map, and a calendar entry carrying the hall's name and no place, until
    /// the reader happened to open its sheet or asked Settings to go over
    /// every hall they hold. Adding an event is the reader saying they mean to
    /// go, which is the same standing an import's arrival has, so it is placed
    /// on the same terms.
    ///
    /// Two requests rather than one, because a search row carries no address:
    /// Eventernote publishes that on the event's own page, and nothing is
    /// placed without one. So the page is read first wherever the row never
    /// carried it — which is also what fills in the times the Passport adds
    /// up, and the billing its sheet lists.
    ///
    /// Queued and taken one at a time, because a reader can add a screenful of
    /// rows faster than either site answers and a burst of searches is exactly
    /// what gets this app throttled. Never upgraded from the block to the
    /// building, for the reason an import's run never is: that one is the
    /// sheet's to ask, for the hall in front of the reader.
    private func placeAdded(_ event: Event) {
        guard venues != nil, !arrivals.contains(event.id) else { return }
        arrivals.append(event.id)
        // One runner, whatever it is handed. A second would be two bursts
        // rather than one queue.
        guard arrivalPlacement == nil else { return }
        arrivalPlacement = Task { [weak self] in
            while let next = self?.arrivals.first {
                self?.arrivals.removeFirst()
                await self?.placeArrival(next)
            }
            self?.arrivalPlacement = nil
        }
    }

    /// One arrival: its own page wherever the row it came from carried no
    /// address, and then its hall.
    ///
    /// Read afresh rather than taken as handed in, because the reader may have
    /// taken it back out again while the queue was working — and an event no
    /// longer theirs is not one to go asking about.
    private func placeArrival(_ id: Event.ID) async {
        guard var event = event(id: id), isInLibrary(event) else { return }
        if event.publishedAddress == nil {
            event = await loadDetail(for: event)
        }
        guard event.publishedAddress != nil else { return }

        let outcome = await venues?.placeUnplaced([event]) { _ in }
        // `placeUnplaced` deliberately says nothing on ``VenuePlaces/placings``
        // — a run of hundreds would ask for hundreds of mirrors — so the entry
        // this has just given a place to is mirrored from here. Only where
        // something was actually placed: a hall already known is no news, and
        // neither is a hall nobody can find.
        if case .refreshed(let found, _) = outcome, found > 0 {
            if retimeEvents() { persist() }
            mirrorSoon()
        }
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
    ///
    /// Not held to ``PageReads/freshness``, however recently a page was read:
    /// this is the reader tapping Refresh, and a refresh they asked for reads
    /// what they asked it to. The window governs only what the app reads by
    /// itself — see ``isStale(_:)``.
    private var needsReading: [Event] {
        library.filter { $0.isUpcoming || !$0.isDetailed }
    }

    /// Reads those pages a few at a time, reporting whether the pass got
    /// through at all. An event whose page failed keeps the copy already held.
    ///
    /// Stops handing out pages the moment the site says it is being asked too
    /// often. The four already in flight are let finish, and everything not
    /// reached keeps what it had — the next refresh picks it up, and carrying
    /// on would only have been refused for longer.
    private func reimportDetails() async -> Bool {
        let events = needsReading
        guard !events.isEmpty else { return true }
        refreshStage = .reimporting(read: 0, total: events.count)

        let client = client
        let asked = Date.now
        let inFlight = 4
        var read = 0
        var landed = 0
        var throttled = false

        await withTaskGroup(of: (event: Event?, throttled: Bool).self) { group in
            var next = events.startIndex
            func addTask() {
                guard next < events.endIndex else { return }
                let event = events[next]
                next = events.index(after: next)
                group.addTask {
                    do {
                        return (try await client.detail(for: event), false)
                    } catch {
                        return (nil, (error as? EventernoteClient.Failure)?.isRateLimited == true)
                    }
                }
            }

            for _ in 0 ..< min(inFlight, events.count) { addTask() }
            for await result in group {
                read += 1
                if let event = result.event {
                    apply(event, asked: asked)
                    landed += 1
                }
                if result.throttled { throttled = true }
                refreshStage = .reimporting(read: read, total: events.count)
                if !throttled { addTask() }
            }
        }

        if throttled, refreshFailure == nil {
            refreshFailure = String(localized: "Eventernote is asking the app to slow down. What did arrive was kept; try again in a few minutes.")
        }

        guard landed > 0 else {
            if refreshFailure == nil {
                refreshFailure = String(localized: "Could not reach Eventernote. Showing the last import.")
            }
            return false
        }
        // Some pages landed and some did not. "Updated" would say every event
        // on screen is current, when the ones that failed are still showing
        // their last read.
        let missed = events.count - landed
        if missed > 0, refreshFailure == nil {
            refreshFailure = String(localized: "\(missed) of \(events.count) event pages could not be read. Those events keep what was read before.")
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
    /// Two rules keep this from talking over the reader:
    ///
    /// - An event they removed is imported again, because the account still
    ///   lists it and the account is what they asked to be read. What a removal
    ///   settles is their own devices, through the tombstone a merge honours;
    ///   nothing here has ever claimed it settles Eventernote too.
    /// - A page that fails does not discard the pages that worked. The import
    ///   adopts what it read and says it stopped short.
    ///
    /// What the reader wrote — a note, a ticket status — is never written by an
    /// import at all. Nor is anything else: an import used to rule on the
    /// tracking they had left blank, and there is nothing left for it to rule
    /// on, because putting the event in the library is the whole of what the
    /// account evidences.
    ///
    /// Reports whether anything was adopted, so ``refresh()`` knows whether the
    /// pass is worth stamping.
    private func importHistory() async -> Bool {
        guard let handle = eventernoteHandle else { return false }
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

        archive.lastImported = .now
        importSummary = ImportSummary(read: distinct.count, added: adopt(distinct))
        return true
    }

    /// Folds an imported history into the archive under the rules above, and
    /// answers how many events it grew the library by.
    ///
    /// Nothing but membership and the event's own facts is written. An import
    /// used to fill in the tracking the reader had left blank — how interested
    /// they were, whether they turned up — and there is nothing left to fill:
    /// putting the event in the library is the whole of what the account
    /// evidences, and the badge is read from that. What the reader wrote
    /// themselves was never an import's to touch and still is not.
    @discardableResult
    private func adopt(_ imported: [Event]) -> Int {
        let now = Date.now
        var added = 0

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
        }
        return added
    }

    // MARK: - Syncing

    /// Asks iCloud for whatever another device wrote and sends whatever this
    /// one has waiting — or, the first time, starts syncing at all.
    func syncNow() async {
        // A ticket bought on the other device is a calendar entry owed on this
        // one, so the mirror runs whether or not iCloud is in the picture.
        defer { Task { await mirrorCalendar() } }
        guard iCloudSyncEnabled, let cloud else { return }
        await cloud.sync(for: self)
    }

    /// Flushes a pending write immediately.
    ///
    /// Edits are written after a short pause; the app leaving the foreground
    /// cuts that pause short, so the last one is committed here rather than lost.
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        archive = archive.pruned()
        writeFile()
        if iCloudSyncEnabled, let cloud {
            Task { await cloud.noteChanges() }
        }
    }

    /// This device's side of the exchange — see ``CloudSync``.
    var archiveForCloud: LibraryArchive { archive }

    /// Folds in what another device wrote. Merged rather than adopted: this
    /// device may have edits of its own that have not gone out yet, and the
    /// save behind this sends whatever the merge made of the two.
    func cloudDelivered(_ slices: [LibraryArchive]) {
        archive = archive.merging(contentsOf: slices)
        retimeEvents()
        lastSynced = .now
        persist()
    }

    func cloudReported(_ outcome: CloudSync.Outcome) {
        guard iCloudSyncEnabled else { return }
        syncStatus = outcome
        if outcome == .synced { lastSynced = .now }
    }

    /// iCloud stopped being somewhere this library may go.
    ///
    /// A different account signed in, or the reader deleted Eventrail's data
    /// from iCloud. Syncing stops rather than carrying on quietly: in the
    /// first case the library on this device was gathered under the account
    /// that just left, and merging it into somebody else's would put one
    /// reader's records in the other's iCloud; in the second, sending it all
    /// straight back would undo what the reader just did. Turning the switch
    /// back on is the reader saying otherwise.
    func cloudStopped(_ outcome: CloudSync.Outcome) {
        // The switch clears the status on its way down, so the reason is
        // written after it rather than before.
        iCloudSyncEnabled = false
        syncStatus = outcome
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
            calendarStatus = await calendar.stop()
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

    /// How the halls the reader holds were placed, and how many are not yet —
    /// what Venue Locations counts beside each of the three answers.
    var venueBreakdown: VenuePlaces.Breakdown {
        venues?.breakdown(for: placeableEvents) ?? .init()
    }

    /// Asks Maps again about every hall the reader holds, and then writes what
    /// comes back into their calendar.
    ///
    /// The one place anything looks up halls in bulk — see ``VenuePlaces`` for
    /// why that is otherwise avoided, and why this takes minutes rather than
    /// seconds. The mirror afterwards is the point as much as the lookup is:
    /// entries written while a hall was still unplaced carry its name and no
    /// map, and nothing else goes back to correct them.
    ///
    /// `includingMaps` is the switch beside the button: off, the halls Maps
    /// already placed are left as they are — see ``VenuePlaces/refresh(_:includingMaps:onProgress:)``.
    func refreshVenues(includingMaps: Bool) async {
        guard let venues, !isRefreshingVenues else { return }
        // Nothing counted yet: how many halls there are is the refresh's own
        // answer, once it has sorted the events into the halls they share.
        venueStatus = .asking(done: 0, of: 0)
        venueStatus = await venues.refresh(placeableEvents, includingMaps: includingMaps) { progress in
            self.venueStatus = progress
        }
        if retimeEvents() { persist() }
        await mirrorCalendar()
    }

    // MARK: - What this device has read

    /// Forgets which pages this device has read, so every sheet opened next
    /// reads its page again.
    ///
    /// Nothing the reader owns goes with it: what was read from those pages is
    /// in the library already, and this is only the note saying not to ask for
    /// them again yet.
    func forgetReadPages() {
        pageReads?.clear()
    }

    /// Reads every event held here on its hall's own clock, and says whether
    /// any of them moved.
    ///
    /// The other half of ``Event/published(in:)``. An import reads every page
    /// on Tokyo time because that is all the page says — Eventernote prints a
    /// clock and never a zone — and a night in Taipei or Shanghai is published
    /// in the hall's clock like every other. So the correction waits on the one
    /// thing that knows where the hall stands, which is the placing, and is
    /// applied here whenever a placing lands.
    ///
    /// Reads what ``VenuePlaces`` has already written down and asks nothing: a
    /// pass over the whole archive must not become a run of searches, which is
    /// the rule the calendar mirror is built on as well.
    ///
    /// Written into the archive rather than worked out where the times are
    /// read, because it is the instant that is wrong rather than the way it is
    /// shown — the library's order, whether a night has passed, the calendar
    /// entry and its alert are all made of it, and none of them should have to
    /// know about zones.
    @discardableResult
    private func retimeEvents() -> Bool {
        guard let venues else { return false }
        var moved = false
        let zones = venues.timeZones(for: Array(archive.events.values) + Array(seen.values))
        for (id, zone) in zones {
            if let event = archive.events[id], event.timeZone != zone {
                archive.events[id] = event.published(in: zone)
                moved = true
            }
            // An event met in Search and not kept is held here and nowhere
            // else, and its sheet is the one place the hall was looked up
            // from. Nothing to persist — it is not the reader's yet — so this
            // deliberately does not count as a move.
            if let event = seen[id], event.timeZone != zone {
                seen[id] = event.published(in: zone)
            }
        }
        return moved
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
                // A hall that has just been placed is also a hall whose clock
                // has just been settled, and an event at it may owe its
                // calendar entry a different hour as well as a map.
                if self?.retimeEvents() == true { self?.persist() }
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

    // MARK: - Persisting

    /// Coalesces the writes a burst of edits produces — typing in a note field
    /// should not touch the disk, or iCloud, on every keystroke.
    private func persist() {
        pendingSave?.cancel()
        // Pruning here, not only on merge: an event the reader removed must stop
        // being uploaded, not linger in iCloud until some other device syncs.
        archive = archive.pruned()
        revision += 1
        guard file != nil || (iCloudSyncEnabled && cloud != nil) else { return }

        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            let file = self.fileToWrite()
            let archive = self.archive
            let copies = self.recoveredCopies
            let saved = await Task.detached(priority: .utility) {
                let saved = file?.save(archive) ?? false
                if saved { file?.discard(copies) }
                return saved
            }.value
            if saved { self.recoveredCopies.removeAll(where: copies.contains) }
            guard !Task.isCancelled else { return }
            // The records that changed are worked out against what iCloud was
            // last told, so an edit sends the one record it touched.
            if self.iCloudSyncEnabled, let cloud = self.cloud {
                await cloud.noteChanges()
            }
            // The calendar follows the same pause as the disk write: a ticket
            // toggled twice while deciding should reach EventKit once.
            await self.mirrorCalendar()
        }
    }

    /// Writes the library to disk now, where it is safe to.
    private func writeFile() {
        guard let file = fileToWrite(), file.save(archive) else { return }
        file.discard(recoveredCopies)
        recoveredCopies = []
    }

    /// The file to save to, or nil while the one on disk could not be read.
    ///
    /// A blocked file is read again first — it is usually a device that had
    /// not been unlocked yet, and by the next edit it has — and what it holds
    /// is folded into the library in memory before anything is written over
    /// it, the same merge a launch would have made.
    private func fileToWrite() -> LibraryFile? {
        guard let file else { return nil }
        guard libraryFileIsBlocked else { return file }
        let contents = file.load()
        guard !contents.isBlocked else { return nil }
        libraryFileIsBlocked = false
        unreadableLibraryFiles = contents.unreadable
        recoveredCopies = Array(Set(recoveredCopies).union(contents.recoveredCopies))
        archive = archive.merging(contents.archive).pruned()
        revision += 1
        retimeEvents()
        return file
    }

    // MARK: - Grouping

    func events(matching filter: LibraryFilter) -> [Event] {
        events(in: library, matching: filter)
    }

    /// The same half of a list the caller has already chosen — the favorites,
    /// say, rather than the whole library.
    func events(in pool: some Sequence<Event>, matching filter: LibraryFilter) -> [Event] {
        filter.rows(of: pool)
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
            return EventGroup.byMonth(events)
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
        /// Notes and ticket statuses brought back.
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
        retimeEvents()
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
    /// reader has already been to.
    ///
    /// Counted over the library rather than over the appearances a performer's
    /// page has read so far, so the number is the whole of it however little of
    /// that listing has been paged in.
    func attendedCount(billing name: String) -> Int {
        attendedEvents.filter { event in
            event.performers.contains { $0.name == name }
        }.count
    }

    /// How many events in the library at this hall the reader has already been
    /// to, counted over the library for the reason above.
    ///
    /// Matched on the name the site printed, which is the only thing a listing
    /// row publishes about a hall and so the only thing every event in the
    /// library carries — an event imported from a search row has no place id
    /// to match on.
    func attendedCount(atVenue name: String) -> Int {
        attendedEvents.filter { $0.venue == name }.count
    }

    // MARK: - Profile statistics

    /// What the reader went to: the library's own past.
    ///
    /// Keeping an event is what says they mean to go, so an event still in the
    /// library once its date has passed is one they went to. Nothing else is
    /// recorded, and nothing else needs to be — an event they did not go to is
    /// one they take out.
    var attendedEvents: [Event] {
        library.filter { !$0.isUpcoming }
    }

    var venuesVisited: Int {
        Set(attendedEvents.map(\.venue)).count
    }

    var performersSeen: Int {
        Set(attendedEvents.flatMap { $0.performers.map(\.name) }).count
    }

    /// How many nights the reader has stood at: the whole of the library's
    /// past, and what the lottery count below is out of.
    ///
    /// The one thing the reader fills in by hand is only ever part-filled, so
    /// it says what it is counted out of. A total over records nobody wrote is
    /// not a total.
    ///
    /// It is also the first of the three figures on the Me tab's Passport
    /// card. All three are read over ``attendedEvents`` and none of them is cut
    /// to a year: three counts side by side are read as one reading of a
    /// library, so one of them answering for this year alone while the other
    /// two answer for all of it is a figure nobody can compare.
    var eventsAttended: Int {
        attendedEvents.count
    }

    /// How many lottery entries the reader put in for the nights they went to.
    ///
    /// The nights they went to, and not the ones still coming: an entry written
    /// down for a lottery still open is kept, and joins this the day the event
    /// passes — the same rule the venue and performer counts above already
    /// follow, so the four numbers are four readings of one library.
    var lotteryEntries: Int {
        attendedEvents.reduce(0) { $0 + (tracking(for: $1).lotteryEntries ?? 0) }
    }

    /// How many of those nights have a lottery count at all. A blank is not a
    /// zero, so it is left out of the total rather than counted as none.
    var lotteryEntriesRecorded: Int {
        attendedEvents.count { tracking(for: $0).lotteryEntries != nil }
    }
}
