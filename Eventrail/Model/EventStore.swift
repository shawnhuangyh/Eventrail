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

/// In-memory state for the app's screens.
///
/// Persistence is deliberately absent: the README defers the SwiftData/CloudKit
/// choice until the schema is validated, so this stands in behind the same
/// surface the views will keep using.
@Observable
final class EventStore {
    private(set) var library: [Event]
    private(set) var discoverable: [Event]

    /// The reader's own records, keyed by stable event ID.
    var tracking: [Event.ID: Tracking]
    var favorites: Set<Event.ID> = []

    var iCloudSyncEnabled = true
    private(set) var isRefreshing = false
    private(set) var lastRefreshed: Date? = .now.addingTimeInterval(-12 * 60)

    /// The associated public profile. Unverified: a username is not a login.
    let profileHandle = "@sora_live_note"
    let listedParticipations = 142

    init(
        library: [Event] = SampleData.library,
        discoverable: [Event] = SampleData.discoverable,
        tracking: [Event.ID: Tracking] = SampleData.tracking
    ) {
        self.library = library
        self.discoverable = discoverable
        self.tracking = tracking
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

    func event(id: Event.ID) -> Event? {
        library.first { $0.id == id } ?? discoverable.first { $0.id == id }
    }

    // MARK: - Writing

    func setTracking(_ tracking: Tracking, for event: Event) {
        self.tracking[event.id] = tracking
    }

    func toggleFavorite(_ event: Event) {
        if favorites.contains(event.id) { favorites.remove(event.id) }
        else { favorites.insert(event.id) }
    }

    /// Copying a discovered event into the library is always explicit — a later
    /// import never does it silently, and never undoes it.
    func toggleLibraryMembership(_ event: Event) {
        if let index = library.firstIndex(where: { $0.id == event.id }) {
            library.remove(at: index)
            if tracking[event.id]?.isEmpty ?? true { tracking[event.id] = nil }
        } else {
            library.append(event)
            if tracking[event.id] == nil { tracking[event.id] = Tracking(interest: .interested) }
        }
    }

    /// Stands in for the import adapter. A real refresh replaces only imported
    /// fields and leaves ``tracking`` untouched; on failure it keeps the last
    /// successful snapshot and the timestamp that goes with it.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        try? await Task.sleep(for: .seconds(1.3))
        isRefreshing = false
        lastRefreshed = .now
    }

    // MARK: - Grouping

    func events(matching filter: LibraryFilter) -> [Event] {
        switch filter {
        case .upcoming:
            library.filter(\.isUpcoming).sorted { $0.startsAt < $1.startsAt }
        case .past:
            library.filter { !$0.isUpcoming }.sorted { $0.startsAt > $1.startsAt }
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

    // MARK: - Search

    /// Searches the library and the public pages together, the way the Search
    /// tab presents them — library membership is shown per row.
    func searchResults(query: String, scope: SearchScope) -> [Event] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }

        var seen = Set<Event.ID>()
        let pool = (discoverable + library).filter { seen.insert($0.id).inserted }

        return pool.filter { event in
            switch scope {
            case .events:
                [event.title, event.venue, event.artist]
                    .contains { $0.lowercased().contains(needle) }
            case .performers:
                event.performers.contains { $0.name.lowercased().contains(needle) }
            }
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
        let upcoming = events.filter(\.isUpcoming).sorted { $0.startsAt < $1.startsAt }
        let past = events.filter { !$0.isUpcoming }.sorted { $0.startsAt > $1.startsAt }
        return upcoming + past
    }

    // MARK: - Profile statistics

    private var attendedEvents: [Event] {
        library.filter { tracking(for: $0).attendance == .attended }
    }

    var eventsThisYear: Int {
        let year = Calendar.current.component(.year, from: .now)
        return library.filter { Calendar.current.component(.year, from: $0.startsAt) == year }.count
    }

    var venuesVisited: Int {
        Set(attendedEvents.map(\.venue)).count
    }

    var performersSeen: Int {
        Set(attendedEvents.flatMap { $0.performers.map(\.name) }).count
    }
}
