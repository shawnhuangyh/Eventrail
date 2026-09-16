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
/// import replaces ``library`` entries and never reads or writes ``tracking``
/// or ``favorites``. The whole thing is mirrored to ``LibraryFile`` after each
/// change so what the reader adds survives the app being closed.
@Observable
final class EventStore {
    private(set) var library: [Event]
    private(set) var tracking: [Event.ID: Tracking]
    private(set) var favorites: Set<Event.ID>
    private(set) var recentSearches: [String]

    private(set) var isRefreshing = false
    private(set) var lastRefreshed: Date?
    /// Why the last import stopped short, if it did. A failed import keeps the
    /// previous snapshot and the timestamp that goes with it.
    private(set) var refreshFailure: String?

    /// Events met in search but never added. A favourite, or a sheet still open,
    /// has to keep resolving after the search that found it is gone.
    private var seen: [Event.ID: Event] = [:]

    private let file: LibraryFile?
    private let client: EventernoteClient
    private var pendingSave: Task<Void, Never>?

    /// The default store reads the reader's own library from disk. Previews and
    /// the playground pass events in and leave `file` nil, so nothing they do
    /// is written anywhere.
    init(
        file: LibraryFile? = .shared,
        client: EventernoteClient = .shared,
        library: [Event] = [],
        tracking: [Event.ID: Tracking] = [:]
    ) {
        self.file = file
        self.client = client

        let archive = file?.load() ?? LibraryArchive()
        self.library = archive.events.isEmpty ? library : archive.events
        self.tracking = archive.events.isEmpty ? tracking : archive.tracking
        favorites = archive.favorites
        recentSearches = archive.recentSearches
        lastRefreshed = archive.lastRefreshed
    }

    // MARK: - Reading

    func tracking(for event: Event) -> Tracking {
        tracking[event.id] ?? Tracking()
    }

    func status(for event: Event) -> TrackingStatus {
        TrackingStatus(tracking(for: event))
    }

    func isInLibrary(_ event: Event) -> Bool {
        library.contains { $0.id == event.id }
    }

    func isFavorite(_ event: Event) -> Bool {
        favorites.contains(event.id)
    }

    /// The freshest copy of an event this app holds, wherever it came from.
    func event(id: Event.ID) -> Event? {
        library.first { $0.id == id } ?? seen[id]
    }

    // MARK: - Writing

    func setTracking(_ tracking: Tracking, for event: Event) {
        self.tracking[event.id] = tracking.isEmpty ? nil : tracking
        scheduleSave()
    }

    func toggleFavorite(_ event: Event) {
        if favorites.contains(event.id) { favorites.remove(event.id) } else { favorites.insert(event.id) }
        // A favourite outside the library still has to resolve to an event.
        seen[event.id] = event
        scheduleSave()
    }

    /// Copying an event found in search into the library is always explicit — an
    /// import never does it silently, and never undoes it.
    func toggleLibraryMembership(_ event: Event) {
        if let index = library.firstIndex(where: { $0.id == event.id }) {
            seen[event.id] = library[index]
            library.remove(at: index)
            if tracking[event.id]?.isEmpty ?? true { tracking[event.id] = nil }
        } else {
            library.append(event)
            if tracking[event.id] == nil { tracking[event.id] = Tracking(interest: .interested) }
        }
        scheduleSave()
    }

    /// Holds on to what a search turned up, without adding any of it.
    func remember(_ events: [Event]) {
        for event in events where library.contains(where: { $0.id == event.id }) == false {
            seen[event.id] = event
        }
    }

    func remember(search term: String) {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        recentSearches.insert(term, at: 0)
        recentSearches = Array(recentSearches.prefix(8))
        scheduleSave()
    }

    func clearRecentSearches() {
        recentSearches = []
        scheduleSave()
    }

    /// Folds a freshly imported copy of an event back in, wherever it is held.
    private func apply(_ imported: Event) {
        if let index = library.firstIndex(where: { $0.id == imported.id }) {
            library[index] = imported
        }
        if seen[imported.id] != nil || !isInLibrary(imported) {
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
        scheduleSave()
        return imported
    }

    /// Re-imports every event in the library from its public page.
    ///
    /// Only imported fields are replaced. On failure the previous snapshot and
    /// its timestamp are kept: the app reports when it last *succeeded*, never
    /// that what it holds is current.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshFailure = nil
        defer { isRefreshing = false }

        let events = library
        guard !events.isEmpty else {
            lastRefreshed = .now
            scheduleSave()
            return
        }

        let imported = await Self.reimport(events, using: client)
        guard !imported.isEmpty else {
            refreshFailure = String(localized: "Could not reach Eventernote. Showing the last import.")
            return
        }
        for event in imported { apply(event) }
        lastRefreshed = .now
        scheduleSave()
    }

    /// Fetches event pages a few at a time. Whatever comes back is used; an
    /// event whose page failed keeps the copy already held.
    private nonisolated static func reimport(
        _ events: [Event], using client: EventernoteClient
    ) async -> [Event] {
        let inFlight = 4
        return await withTaskGroup(of: Event?.self) { group in
            var imported: [Event] = []
            var next = events.startIndex

            func addTask() {
                guard next < events.endIndex else { return }
                let event = events[next]
                next = events.index(after: next)
                group.addTask { try? await client.detail(for: event) }
            }

            for _ in 0 ..< min(inFlight, events.count) { addTask() }
            for await result in group {
                if let result { imported.append(result) }
                addTask()
            }
            return imported
        }
    }

    // MARK: - Persisting

    /// Writes now, rather than after the usual pause. Called when the app is
    /// about to go to the background, where the pending write would be lost.
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        file?.save(archive)
    }

    private var archive: LibraryArchive {
        LibraryArchive(
            events: library, tracking: tracking, favorites: favorites,
            recentSearches: recentSearches, lastRefreshed: lastRefreshed
        )
    }

    /// Coalesces the writes a burst of edits produces — typing in a note field
    /// should not touch the disk on every keystroke.
    private func scheduleSave() {
        pendingSave?.cancel()
        guard let file else { return }
        let archive = archive
        pendingSave = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) { file.save(archive) }.value
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
        let events = favorites.compactMap { event(id: $0) }
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
