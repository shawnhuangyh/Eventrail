import Foundation
import OSLog
import SwiftData
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

    /// The glyph beside the option in the Sort menu at the foot of an event
    /// list.
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

/// Every write to the reader's library.
///
/// The library itself is ``LibraryDatabase``: one SwiftData row per record,
/// which the screens read with `@Query` and SwiftData syncs when the reader
/// has iCloud Sync on. This is where it is written. What the reader decides
/// about an event goes into its ``LibraryEntry`` and nowhere else, and only
/// when they decide it — a removal is `inLibrary` false rather than a deleted
/// row, and an import of their account adds what it still lists. What
/// Eventernote says about it goes into its ``LibraryEvent``, which any read
/// of its page may rewrite, and which never says whether the reader kept it.
@Observable
@MainActor
final class EventStore {
    private static let log = Logger(subsystem: "moe.shawn.Eventrail", category: "library")

    /// Where the library is kept.
    let database: LibraryDatabase

    /// Every event's facts, by event id — how anything holding an event finds
    /// the freshest copy of it without a query of its own. Rebuilt whenever
    /// the rows may have changed underneath: a launch, another device's
    /// changes, a restore, the store opened again. Where two rows are about
    /// one event, it holds the one ``LibraryDatabase/deduplicate(in:)`` keeps.
    private var rows: [Event.ID: LibraryEvent] = [:]
    /// What the reader has said about each event, by event id, kept the same
    /// way.
    private var entries: [Event.ID: LibraryEntry] = [:]
    /// Every Following date's read, by event id, kept the same way.
    private var readMarks: [Event.ID: FollowingReadMark] = [:]
    private var performerRows: [Int: FollowedPerformer] = [:]
    private var settingsRow: LibrarySettings?

    private(set) var isRefreshing = false
    /// Why the last import stopped short, if it did. A failed import keeps the
    /// previous snapshot and the timestamp that goes with it.
    private(set) var refreshFailure: String?

    /// How syncing stands — see ``LibraryDatabase/SyncStatus``.
    var syncStatus: LibraryDatabase.SyncStatus? { database.syncStatus }
    var lastFetched: Date? { database.lastFetched }

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
            // Written out first: the store is about to be opened again the
            // other way, and the rows held here belong to the old container.
            // The rows are read again as it opens (``LibraryDatabase/onReopened``).
            saveNow()
            database.setSyncing(iCloudSyncEnabled)
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

    /// How many library files an older build set aside unread and this one
    /// cannot read either — see ``LibraryFile/load()``. Settings says so,
    /// since the library on screen is missing what they hold.
    private(set) var unreadableLibraryFiles = 0

    /// Whether the store would not open this launch, or the library file an
    /// older build kept would not open to be moved in — a device not yet
    /// unlocked since it started, most likely. Nothing is written over either
    /// meanwhile; coming back to the app tries again (``syncNow()``), and
    /// Settings says so while it lasts.
    private(set) var libraryFileIsBlocked = false

    /// Why the last save did not reach the file, while nothing has been saved
    /// since. The edits stay in the rows, and every screen shows them; they
    /// are written with the next save, and tried again on coming back to the
    /// app (``syncNow()``). Settings says so meanwhile, since an app closed
    /// now would lose them.
    private(set) var saveFailure: String?

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

    /// The JSON library older builds kept, moved into ``database`` — see
    /// ``LibraryDatabase/moveIn(from:)``.
    private let libraryFile: LibraryFile?
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

    /// The default store opens the reader's own library, synced or not as
    /// they last said. Previews and tests hand in a database held in memory
    /// and leave the file, the calendar and the venues out, so nothing they
    /// do is written or synced anywhere.
    init(
        database: LibraryDatabase? = nil,
        libraryFile: LibraryFile? = .shared,
        calendar: CalendarSync? = .shared,
        venues: VenuePlaces? = .shared,
        pageReads: PageReads? = .shared,
        client: EventernoteClient = .shared,
        library: [Event] = [],
        tracking: [Event.ID: Tracking] = [:],
        follows: [PerformerProfile] = []
    ) {
        // Off until the reader says otherwise, the same as the calendar. A
        // store handed its database never syncs.
        let syncing = database == nil && UserDefaults.standard.bool(forKey: Self.syncPreferenceKey)
        self.database = database ?? LibraryDatabase(syncing: syncing)
        self.libraryFile = libraryFile
        self.calendar = calendar
        self.venues = venues
        self.pageReads = pageReads
        self.client = client

        iCloudSyncEnabled = syncing
        calendarSyncEnabled = calendar != nil
            && UserDefaults.standard.bool(forKey: Self.calendarPreferenceKey)
        preciseVenuesEnabled = venues?.usesOpenStreetMap ?? false

        moveInLibraryFile()
        seed(library: library, tracking: tracking, follows: follows)
        self.database.onRemoteChanges = { [weak self] in self?.remoteChangesArrived() }
        self.database.onSyncStopped = { [weak self] in self?.iCloudSyncEnabled = false }
        self.database.onReopened = { [weak self] in self?.reindex() }

        // A hall being placed is owed a mirror whether or not this device syncs.
        observeVenuePlacings()

        // Written back rather than only held: what this corrects is a night
        // abroad imported before its hall was placed, and correcting it once a
        // launch would be correcting it forever.
        if retimeEvents() { save() }
    }

    isolated deinit {
        venuePlacings?.cancel()
        pendingMirror?.cancel()
        pendingSave?.cancel()
    }

    /// Moves the JSON library an older build kept into the store, and folds
    /// back any copy one set aside unread — see ``LibraryDatabase/moveIn(from:)``.
    /// Tried again while either would not open.
    private func moveInLibraryFile() {
        if database.isBlocked { database.reopen() }
        let contents = libraryFile.flatMap { database.moveIn(from: $0) }
        unreadableLibraryFiles = contents?.unreadable ?? 0
        libraryFileIsBlocked = database.isBlocked || contents?.isBlocked == true
        reindex()
    }

    /// What a preview is handed, written into its empty store.
    private func seed(library: [Event], tracking: [Event.ID: Tracking], follows: [PerformerProfile]) {
        if entries.isEmpty {
            for event in library {
                edit(event) { answers in
                    answers.inLibrary = true
                    answers.tracking = tracking[event.id] ?? Tracking()
                }
            }
        }
        if performerRows.isEmpty {
            for performer in follows {
                let row = makePerformerRow(for: performer.id)
                row.follow = Stamped(true)
                row.profile = performer
            }
        }
        commit()
    }

    // MARK: - Rows

    /// Reads every row into the index, after anything that may have changed
    /// them underneath.
    private func reindex() {
        let context = database.context
        rows = LibraryDatabase.index((try? context.fetch(FetchDescriptor<LibraryEvent>())) ?? [],
                                     by: \.eventID, preferring: LibraryEvent.isPreferred)
        entries = LibraryDatabase.index((try? context.fetch(FetchDescriptor<LibraryEntry>())) ?? [],
                                        by: \.eventID, preferring: LibraryEntry.isPreferred)
        readMarks = LibraryDatabase.index((try? context.fetch(FetchDescriptor<FollowingReadMark>())) ?? [],
                                          by: \.eventID, preferring: FollowingReadMark.isPreferred)
        performerRows = LibraryDatabase.index((try? context.fetch(FetchDescriptor<FollowedPerformer>())) ?? [],
                                              by: \.actorID, preferring: FollowedPerformer.isPreferred)
        settingsRow = (try? context.fetch(FetchDescriptor<LibrarySettings>()))?
            .sorted(by: LibrarySettings.isPreferred).first
        // Anything may have changed underneath, so no kept copy is trusted.
        stale = nil
        revision += 1
    }

    /// The events these entries stand for — what a screen's `@Query` of
    /// ``LibraryEntry/library`` or ``LibraryEntry/favorites`` is turned into,
    /// with the flag that query asked for.
    ///
    /// Each entry answers through the one kept for its event, so two entries
    /// for one event — there for the moment between an import and its fold —
    /// list it once, and as the one written last says. Its facts come from its
    /// ``LibraryEvent``, or from the copy the entry carries where that has not
    /// arrived: an event the reader kept is always listed.
    ///
    /// Read once per ``revision`` and kept: a screen asks for its list several
    /// times a redraw, every tab redraws when any row changes, and reading
    /// nine hundred rows' forty columns each time cost a tenth of a second a
    /// redraw. Every write here bumps `revision` and names the events it
    /// touched (``save()``), and every change that lands from elsewhere bumps
    /// it and forgets them all (``reindex()``), so a kept copy never outlives
    /// what its rows say. Reading `revision` here is also what redraws a
    /// screen served from the kept copies.
    func events(of entries: some Sequence<LibraryEntry>, where flag: KeyPath<LibraryEntry, Bool>) -> [Event] {
        if convertedAt != revision {
            if let stale {
                for id in stale { converted[id] = nil }
            } else {
                converted.removeAll(keepingCapacity: true)
            }
            stale = []
            convertedAt = revision
        }
        var listed = Set<Event.ID>()
        return entries.compactMap { queried in
            let id = queried.eventID
            guard listed.insert(id).inserted else { return nil }
            // The index can be a moment behind a query that has just seen an
            // import land; the entry in hand stands until it catches up.
            let entry = self.entries[id] ?? queried
            guard entry[keyPath: flag] else { return nil }
            if let kept = converted[id] { return kept }
            let event = rows[id]?.facts ?? entry.kept
            converted[id] = .some(event)
            return event
        }
    }

    /// The row an event's facts are written to, made where there is none.
    private func makeRow(for id: Event.ID) -> LibraryEvent {
        if let row = rows[id] { return row }
        let row = LibraryEvent(eventID: id)
        database.context.insert(row)
        rows[id] = row
        return row
    }

    /// Writes what the reader has just said about an event into its entry.
    ///
    /// Nothing is written where nothing changed, so an entry is only ever sent
    /// with an answer somebody gave. Where something did, the entry takes the
    /// moment — which is what keeps it over an older copy — and the event as
    /// it now stands, so a device its facts have not reached can still list
    /// it.
    ///
    /// `keepingFacts` writes the event into its ``LibraryEvent`` too, for a
    /// change that is about the event as the reader sees it; a removal leaves
    /// the facts where they are.
    private func edit(_ event: Event, keepingFacts: Bool = true, _ change: (inout LibraryEntry.Answers) -> Void) {
        let held = entries[event.id]
        var answers = held?.answers ?? LibraryEntry.Answers()
        change(&answers)
        answers.tracking.edits = [:]
        let given = answers.parts(differingFrom: held?.answers ?? LibraryEntry.Answers())
        guard !given.isEmpty else { return }
        if keepingFacts { keep(event, in: makeRow(for: event.id)) }
        let entry = held ?? LibraryEntry(eventID: event.id)
        if held == nil {
            database.context.insert(entry)
            entries[event.id] = entry
        }
        // Only the parts given now are dated now: an import adding the event
        // says nothing about a heart or a note another device's entry holds.
        let now = Date.now
        entry.give(answers, dated: Dictionary(uniqueKeysWithValues: given.map { ($0, now) }))
        entry.modified = now.toTheMillisecond
        entry.kept = rows[event.id]?.facts ?? event
    }

    private func makeMark(for id: Event.ID) -> FollowingReadMark {
        if let mark = readMarks[id] { return mark }
        let mark = FollowingReadMark(eventID: id)
        database.context.insert(mark)
        readMarks[id] = mark
        return mark
    }

    private func makePerformerRow(for id: Int) -> FollowedPerformer {
        if let row = performerRows[id] { return row }
        let row = FollowedPerformer(actorID: id)
        database.context.insert(row)
        performerRows[id] = row
        return row
    }

    private func makeSettingsRow() -> LibrarySettings {
        if let settingsRow { return settingsRow }
        let row = LibrarySettings()
        database.context.insert(row)
        settingsRow = row
        return row
    }

    // MARK: - Reading

    // Lists are the screens' own `@Query` — see ``LibraryMembership/library``.
    // What is here answers for one event, one performer or the account, for
    // anything holding one; each reads the row itself, so a screen showing it
    // is drawn again when that row changes and not when another does.

    /// The library, for the work done here rather than on a screen: the
    /// calendar, the halls, a refresh.
    private var library: [Event] {
        entries.values.compactMap { $0.inLibrary ? event(id: $0.eventID) : nil }
    }

    /// The library's nights still to come, soonest first — what the watch is
    /// sent (``WatchLink``).
    var upcoming: [Event] {
        library.filter(\.isUpcoming).sorted { $0.sortDate < $1.sortDate }
    }

    var lastRefreshed: Date? { settingsRow?.lastRefreshed }

    /// The Eventernote account the reader imports from, if they have named one.
    var eventernoteHandle: String? { settingsRow?.account }

    /// How the linked account presents itself, as of the last page read from it.
    var eventernoteProfile: LinkedProfile? {
        // Guarded on the handle: an unlink leaves nothing to caption.
        isLinked ? settingsRow?.eventernoteProfile : nil
    }

    /// Whether an account has been named. ``refresh()`` needs one — it is the
    /// list being refreshed from.
    var isLinked: Bool { eventernoteHandle != nil }

    func tracking(for event: Event) -> Tracking {
        entries[event.id]?.tracking ?? Tracking()
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

    func isInLibrary(_ event: Event) -> Bool { entries[event.id]?.inLibrary == true }

    func isFavorite(_ event: Event) -> Bool { entries[event.id]?.isFavorite == true }

    /// Whether emptying the library would still take anything.
    ///
    /// The library and the favorites are not the whole of it: a note or a
    /// ticket status outlives the event it was written on, so this stays true
    /// while either is still held.
    var hasRecordsToDelete: Bool {
        entries.values.contains { !$0.answers.isEmpty }
            || eventernoteHandle != nil
            || performerRows.values.contains(where: \.isFollowing)
    }

    /// The freshest copy of an event this app holds, wherever it came from.
    func event(id: Event.ID) -> Event? {
        rows[id]?.facts ?? entries[id]?.kept ?? seen[id]
    }

    // MARK: - Writing

    func setTracking(_ tracking: Tracking, for event: Event) {
        edit(event) { $0.tracking = tracking }
        save()
    }

    func toggleFavorite(_ event: Event) {
        edit(event) { $0.isFavorite.toggle() }
        save()
    }

    /// Copying an event found in search into the library is always explicit: an
    /// import never does it silently. Taking one back out is explicit too, and
    /// answers only for this device and the reader's other ones — an event the
    /// linked account still lists is imported again on the next refresh.
    func toggleLibraryMembership(_ event: Event) {
        if isInLibrary(event) {
            edit(event, keepingFacts: false) { $0.inLibrary = false }
        } else {
            // Nothing to write down: being in the library is what says the
            // reader means to go, which is what a tracking record used to be
            // opened to say for it.
            edit(event) { $0.inLibrary = true }
            placeAdded(event)
        }
        save()
    }

    /// Takes events out of the library in one go.
    ///
    /// Each one's entry says so rather than going, exactly as a single removal
    /// does: the other device has to be told a removal happened, or it would
    /// hand all of them straight back. It answers for the reader's devices and
    /// not for Eventernote — an event still on the linked account is imported
    /// again by the next refresh. A note written on one outlives it, so that
    /// adding it back brings the note back.
    ///
    /// Favorites are left alone. Hearting an event says "keep this in front of
    /// me", which is a separate answer from whether it is in the library.
    func remove(_ events: some Sequence<Event>) {
        for event in events {
            edit(event, keepingFacts: false) { $0.inLibrary = false }
        }
        save()
    }

    /// Empties the library, and with it the favorites, everything the reader
    /// wrote on top of the events, everyone they follow and the linked
    /// Eventernote account — the account goes so the next refresh does not
    /// import everything straight back. The app's settings stay.
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
    /// is: a dropped record would let the other device's copy come straight back.
    func removeAllEvents() {
        let now = Date.now
        for entry in entries.values where !entry.answers.isEmpty {
            // Every part, given or not: an answer another device gave before
            // this is one the reader asked to be rid of too.
            entry.give(LibraryEntry.Answers(),
                       dated: Dictionary(uniqueKeysWithValues: LibraryEntry.Part.allCases.map { ($0, now) }))
            entry.modified = now.toTheMillisecond
        }
        // Every Following date back to unread, on every device: written as a
        // record with no fingerprint rather than dropped, or the other
        // device's copy of each read would come straight back.
        for mark in readMarks.values {
            if let read = mark.read, read.value.fingerprint != nil {
                mark.read = Stamped(FollowingRead(fingerprint: nil, day: read.value.day), at: now)
            }
        }
        // Everyone followed goes too, as tombstones so the other device's
        // follows do not come back, and with them who they were.
        for row in performerRows.values {
            if row.isFollowing { row.follow = Stamped(false, at: now) }
            row.profile = nil
        }
        // And the account, so the next refresh does not import it all back.
        unlinkAccount()
        save()
    }

    // MARK: - What the reader has looked at on Following and My Events

    /// Whether this copy of a Following row is one the reader has not seen —
    /// see ``FollowingRead``. My Events reads the same record for its
    /// upcoming rows, so a date read on one tab is read on the other.
    func isUnread(_ event: Event) -> Bool { unread(event) != nil }

    /// Why a Following row is unread — new, or changed since it was read —
    /// or nil where it is read.
    func unread(_ event: Event) -> FollowingUnread? {
        var read = LibraryArchive()
        read.followingReads = readMarks[event.id]?.read.map { [event.id: $0] }
        return read.unread(event)
    }

    /// Marks these rows read as the listing prints them now, or unread again.
    /// One write for the lot, however many there are — Select All then Mark
    /// is hundreds of them.
    ///
    /// Written to each date's ``FollowingReadMark`` and never to the event's
    /// own row, so opening an event on a device that has not yet heard it was
    /// removed does not send it back into the library.
    func markRead(_ events: some Sequence<Event>, read: Bool) {
        let now = Date.now
        var changed = false
        for event in events where isUnread(event) == read {
            makeMark(for: event.id).read = Stamped(
                FollowingRead(fingerprint: read ? event.listingFingerprint : nil, day: event.date),
                at: now)
            changed = true
        }
        guard changed else { return }
        save()
    }

    /// Holds on to what a search turned up, without adding any of it.
    func remember(_ events: [Event]) {
        for event in events where rows[event.id]?.facts == nil {
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
        let settings = makeSettingsRow()
        var recents = settings.recentSearches
        recents.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        recents.insert(term, at: 0)
        settings.searches = Stamped(Array(recents.prefix(8)))
        save()
    }

    func clearRecentSearches() {
        let settings = makeSettingsRow()
        settings.searches = Stamped([])
        save()
    }

    /// Writes an event's facts into its row, which is what makes them worth
    /// saving and syncing.
    private func keep(_ event: Event, in row: LibraryEvent) {
        let known = row.facts
        row.write(known.map { $0.isDetailed ? $0.merging(event) : event.merging($0) } ?? event)
    }

    /// Folds a freshly imported copy of an event back in, wherever it is held.
    ///
    /// Every read of an event's own page arrives here, so this is also where
    /// the read is written down — see ``isStale(_:)`` for what that decides.
    /// `asked` is when the page was asked for, so a read the cache was
    /// cleared under is not stamped fresh on its way in.
    ///
    /// A read that found nothing new leaves the row alone — see
    /// ``Event/isSameRead(as:)`` — and is still written down as a read.
    private func apply(_ imported: Event, asked: Date) {
        pageReads?.record(imported.id, asked: asked)
        if let row = rows[imported.id], let held = row.facts {
            guard !imported.isSameRead(as: held) else { return }
            row.write(imported)
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
        save()
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
                save()
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
        makeSettingsRow().lastRefreshed = .now
        save()
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
            if retimeEvents() { save() }
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
            if retimeEvents() { save() }
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
        let changedProfile = profile != settingsRow?.eventernoteProfile
        if changedProfile { makeSettingsRow().eventernoteProfile = profile }

        let follows = adoptFollows(read.favoritePerformers)
        if changedProfile || follows.changed { save() }
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
        var added = 0
        var changed = false

        for performer in performers {
            let row = makePerformerRow(for: performer.id)
            // Anything but an existing `true` is written: a missing record is
            // the first read of them, and a tombstone is undone by the same act
            // that would have to undo it — asking Eventernote again.
            if row.follow?.value != true {
                row.follow = Stamped(true, at: now)
                added += 1
                changed = true
            }
            guard row.profile == nil else { continue }
            // Also reaches a follow recorded before the app kept profiles, which
            // until now had an actor id and no way to name it.
            row.profile = performer
            changed = true
        }

        return changed ? (added, true) : (0, false)
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
        let settings = makeSettingsRow()
        settings.eventernoteProfile = LinkedProfile(name: profile.name, avatarURL: profile.avatarURL)
        guard !isSameAccount else { return save() }

        settings.eventernoteAccount = Stamped<String?>(profile.handle)
        settings.lastImported = nil
        importSummary = nil
        refreshFailure = nil
        save()
    }

    /// Forgets the account. What it already imported stays: those events are in
    /// the library now, and unlinking is about where the app looks next, not
    /// about undoing what the reader has collected.
    func unlinkAccount() {
        guard eventernoteHandle != nil, let settings = settingsRow else { return }
        // A nil inside the stamp rather than a dropped record, so the unlink
        // reaches the other device instead of being merged away.
        settings.eventernoteAccount = Stamped<String?>(nil)
        settings.eventernoteProfile = nil
        settings.lastImported = nil
        importSummary = nil
        refreshFailure = nil
        save()
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

        makeSettingsRow().lastImported = .now
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
        var added = 0

        for event in imported {
            // A removal is not permanent. The account's history is what the
            // reader is asking for when they tap Refresh, so an event they took
            // out comes back if Eventernote still lists it — the same rule the
            // favourites follow. Taking one out for good means taking it off the
            // account, and an event that was never on it stays gone.
            keep(event, in: makeRow(for: event.id))
            if !isInLibrary(event) {
                edit(event) { $0.inLibrary = true }
                added += 1
            }
        }
        return added
    }

    // MARK: - Syncing

    /// Catches up on coming back to the app: tries the store again if it
    /// would not open, starts syncing if the account could not be checked
    /// before, and brings the calendar into line.
    ///
    /// Once syncing, iCloud needs nothing from here — SwiftData imports what
    /// another device wrote and sends what this one has, by itself, and
    /// ``remoteChangesArrived()`` picks up what lands.
    func syncNow() async {
        // A ticket bought on the other device is a calendar entry owed on this
        // one, so the mirror runs whether or not iCloud is in the picture.
        defer { Task { await mirrorCalendar() } }
        if libraryFileIsBlocked { moveInLibraryFile() }
        if saveFailure != nil { commit() }
        database.resumeSyncing()
    }

    /// Flushes a pending write immediately.
    ///
    /// Edits are written after a short pause; the app leaving the foreground
    /// cuts that pause short, so the last one is committed here rather than lost.
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        commit()
    }

    /// Another device's changes have landed and been folded in — see
    /// ``LibraryDatabase/onRemoteChanges``.
    private func remoteChangesArrived() {
        reindex()
        if retimeEvents() { save() }
        mirrorSoon()
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
        if retimeEvents() { save() }
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
        let held = rows.values.compactMap(\.facts)
        let zones = venues.timeZones(for: held + Array(seen.values))
        for (id, zone) in zones {
            if let row = rows[id], let event = row.facts, event.timeZone != zone {
                row.write(event.published(in: zone))
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
                if self?.retimeEvents() == true { self?.save() }
                self?.mirrorSoon()
            }
        }
    }

    /// Mirrors once the halls stop arriving.
    ///
    /// Coalesced the way ``save()`` coalesces a burst of edits, and for the
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

    // MARK: - Saving

    /// Saves a moment from now, coalescing the writes a burst of edits
    /// produces — typing in a note field should not reach the disk, or
    /// iCloud, on every keystroke. The rows themselves change at once, so
    /// every screen already shows the edit.
    private func save() {
        // A note writes on every keystroke: only the rows written go stale,
        // not the nine hundred beside them.
        if stale != nil {
            let context = database.context
            for model in context.changedModelsArray + context.insertedModelsArray {
                if let row = model as? LibraryEvent { stale?.insert(row.eventID) }
                if let entry = model as? LibraryEntry { stale?.insert(entry.eventID) }
            }
        }
        revision += 1
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            commit()
            // The calendar follows the same pause as the save: a ticket
            // toggled twice while deciding should reach EventKit once.
            await mirrorCalendar()
        }
    }

    /// Writes whatever the rows hold that the store does not.
    private func commit() {
        let context = database.context
        // Cleared only where it was set: every assignment redraws whatever
        // reads it, and this runs after every edit.
        guard context.hasChanges else {
            if saveFailure != nil { saveFailure = nil }
            return
        }
        do {
            try context.save()
            if saveFailure != nil { saveFailure = nil }
        } catch {
            Self.log.error("Library could not be saved: \(error.localizedDescription, privacy: .public)")
            saveFailure = error.localizedDescription
        }
    }

    // MARK: - Backups

    /// Everything the reader owns, as one file they can keep outside the app.
    ///
    /// Read out of the store each time it is asked for, including edits not
    /// yet saved; writing it out is the expensive part, and that is the
    /// caller's to do.
    ///
    /// Throws where the store cannot be read. It once stood in an empty
    /// library there, and a backup of nothing looks like any other file —
    /// found out only on the day it is restored.
    func backup() throws -> LibraryBackup {
        LibraryBackup(archive: try LibraryDatabase.archive(in: database.context))
    }

    /// Counts every write made to the library this launch, from here or from
    /// another device.
    ///
    /// A screen holding something derived from the whole library — the export
    /// file, which has to exist before the share sheet can preview it — watches
    /// this rather than trying to spot the change itself. Counting records
    /// would not do: a removal leaves a tombstone behind and an emptied note
    /// keeps its record, so the library can change without changing size.
    private(set) var revision = 0
    @ObservationIgnored private var converted: [Event.ID: Event?] = [:]
    @ObservationIgnored private var convertedAt = -1
    /// The events written since the kept copies were last checked, or nil
    /// where every one of them is to be read again.
    @ObservationIgnored private var stale: Set<Event.ID>? = nil

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
        if database.isBlocked { moveInLibraryFile() }
        let context = database.context
        // Thrown rather than taken as empty: the merge would then have nothing
        // of this device's to weigh the file against, and an older note in the
        // file would be written over the one typed since.
        let before = try LibraryDatabase.archive(in: context)
        let after = before.restoring(backup.archive)
        try LibraryDatabase.apply(after, to: context)
        try context.save()
        reindex()
        if retimeEvents() { save() }
        mirrorSoon()
        let held = Self.held(in: after)
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

    /// Everything the reader has hearted, for the halls worth placing.
    private var favoriteEvents: [Event] {
        entries.values.compactMap { $0.isFavorite ? event(id: $0.eventID) : nil }
    }

    // MARK: - Followed performers

    func isFollowing(_ performer: PerformerProfile) -> Bool {
        performerRows[performer.id]?.isFollowing == true
    }

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
        let row = makePerformerRow(for: performer.id)
        row.follow = Stamped(following)
        // Unfollowing leaves a tombstone but no profile, which is what keeps
        // the store from carrying people it no longer follows all the way to
        // iCloud.
        row.profile = following ? performer : nil
        save()
    }

    /// Stops following someone from a list that shows them, where the profile
    /// is the only handle on who they are.
    func unfollow(_ performer: PerformerProfile) {
        guard isFollowing(performer) else { return }
        toggleFollow(performer)
    }
}
