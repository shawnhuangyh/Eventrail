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
}

/// How the Events tab breaks the list into sections.
enum Grouping: String, CaseIterable, Identifiable, Hashable {
    case date, month, artist

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .date: "Date"
        case .month: "Month"
        case .artist: "Artist"
        }
    }

    /// The trailing half of the toolbar label: "by month".
    var byLabel: LocalizedStringKey {
        switch self {
        case .date: "by date"
        case .month: "by month"
        case .artist: "by artist"
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

    /// Events met in search but never added. Transient: they are not the
    /// reader's, so they are neither saved nor synced until one is kept.
    private var seen: [Event.ID: Event] = [:]

    private let file: LibraryFile?
    private let cloud: CloudSync?
    private let client: EventernoteClient
    private var pendingSave: Task<Void, Never>?
    private var cloudChanges: Task<Void, Never>?

    /// The default store reads the reader's own library from disk and, if they
    /// have sync on, merges whatever iCloud holds. Previews and the playground
    /// pass events in and leave `file` and `cloud` nil, so nothing they do is
    /// written or synced anywhere.
    init(
        file: LibraryFile? = .shared,
        cloud: CloudSync? = .shared,
        client: EventernoteClient = .shared,
        library: [Event] = [],
        tracking: [Event.ID: Tracking] = [:]
    ) {
        self.file = file
        self.cloud = cloud
        self.client = client

        // On by default: a reader with more than one device expects their own
        // records to follow them. A preview has no file and never syncs.
        iCloudSyncEnabled = file != nil
            && (UserDefaults.standard.object(forKey: Self.syncPreferenceKey) as? Bool ?? true)

        var loaded = file?.load() ?? LibraryArchive()
        if loaded.membership.isEmpty, !library.isEmpty {
            loaded.events = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            loaded.membership = library.reduce(into: [:]) { $0[$1.id] = Stamped(true) }
            loaded.tracking = tracking.mapValues { Stamped($0) }
        }
        archive = loaded

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
        pendingSave?.cancel()
    }

    // MARK: - Reading

    var library: [Event] { archive.libraryEvents }

    var recentSearches: [String] { archive.recentSearches.value }

    var lastRefreshed: Date? { archive.lastRefreshed }

    /// The Eventernote account the reader imports from, if they have named one.
    var eventernoteHandle: String? { archive.eventernoteAccount?.value }

    func tracking(for event: Event) -> Tracking {
        archive.tracking[event.id]?.value ?? Tracking()
    }

    func status(for event: Event) -> TrackingStatus {
        TrackingStatus(tracking(for: event))
    }

    func isInLibrary(_ event: Event) -> Bool { archive.isInLibrary(event.id) }

    func isFavorite(_ event: Event) -> Bool { archive.isFavorite(event.id) }

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

    /// Copying an event found in search into the library is always explicit — an
    /// import never does it silently, and never undoes it.
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
    /// would hand all of them straight back.
    ///
    /// Favorites are left alone. Hearting an event says "keep this in front of
    /// me", which is a separate answer from whether it is in the library.
    func remove(_ events: some Sequence<Event>) {
        let now = Date.now
        for event in events { tombstone(event.id, at: now) }
        persist()
    }

    /// Empties the library, and the favorites with it.
    ///
    /// Favorites go too here, unlike a removal of some events: a reader who
    /// asked for every event to go should not be left looking at a Favorites
    /// card that still lists a few.
    func removeAllEvents() {
        let now = Date.now
        for event in library { tombstone(event.id, at: now) }
        for id in archive.favorites.filter(\.value.value).keys {
            archive.favorites[id] = Stamped(false, at: now)
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
    /// With an account linked that is two passes, in this order: the account's
    /// own list first, so whatever it adds is in the library, and then each
    /// event's own page for the times, billing and head count a listing row
    /// never carries. Without an account it is only the second pass, because
    /// there is nothing to import from.
    ///
    /// Only imported fields are replaced. On failure the previous snapshot and
    /// its timestamp are kept: the app reports when it last *succeeded*, never
    /// that what it holds is current.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshFailure = nil
        importSummary = nil
        defer {
            isRefreshing = false
            refreshStage = nil
        }

        // A history that failed still leaves events worth re-reading, so the
        // second pass runs either way and the first failure is the one reported.
        var landed = false
        if eventernoteHandle != nil {
            landed = await importHistory()
        }
        if await reimportDetails() { landed = true }

        // The timestamp moves only when something actually arrived, so a run
        // that reached nothing cannot pass itself off as a successful refresh.
        guard landed else { return }
        archive.lastRefreshed = .now
        persist()
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
        guard profile.handle != eventernoteHandle else { return }
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
        archive.lastImported = nil
        importSummary = nil
        refreshFailure = nil
        persist()
    }

    /// Imports every event the linked account is listed as attending.
    ///
    /// Three rules keep this from talking over the reader:
    ///
    /// - An event they removed stays removed. Its tombstone is honoured, or the
    ///   next import would hand back exactly what they took out.
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
            // The reader took this one out. An import is not a reason to undo that.
            if let membership = archive.membership[event.id], !membership.value { continue }

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
            guard !Task.isCancelled, let self, let outcome else { return }
            self.syncStatus = outcome
            if outcome == .synced { self.lastSynced = .now }
        }
    }

    // MARK: - Grouping

    func events(matching filter: LibraryFilter) -> [Event] {
        switch filter {
        case .upcoming:
            library.filter(\.isUpcoming).sorted { $0.sortDate < $1.sortDate }
        case .past:
            library.filter { !$0.isUpcoming }.sorted { $0.sortDate > $1.sortDate }
        }
    }

    func groups(filter: LibraryFilter, grouping: Grouping) -> [EventGroup] {
        let events = events(matching: filter)
        switch grouping {
        case .date:
            return events.isEmpty ? [] : [EventGroup(id: "all", label: "", events: events)]
        case .month:
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
