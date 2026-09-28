import Foundation
import SwiftData

// What the screens ask the store for with `@Query`, named once so that "the
// library" means the same rows on every screen that shows it.

extension LibraryMembership {
    /// Every event in the library — turned into events through
    /// ``EventStore/events(of:)``, which reads each one's facts from its row.
    static var library: FetchDescriptor<LibraryMembership> {
        FetchDescriptor(predicate: #Predicate { $0.inLibrary == true })
    }
}

extension LibraryEvent {
    /// Every event the reader has hearted, in the library or not.
    static var favorites: FetchDescriptor<LibraryEvent> {
        FetchDescriptor(predicate: #Predicate { $0.isFavorite == true })
    }
}

extension FollowedPerformer {
    /// Everyone the reader follows and the app can name, by name.
    ///
    /// Ordered rather than merely listed: this is a settled list the reader
    /// returns to, and an unordered one would reshuffle the Me card and the
    /// Following filters between launches. A follow with no profile is left
    /// out rather than shown as a blank row: an id is not a person.
    static var followed: FetchDescriptor<FollowedPerformer> {
        FetchDescriptor(
            predicate: #Predicate { $0.isFollowing == true && $0.hasProfile == true },
            sortBy: [SortDescriptor(\.name, comparator: .localizedStandard)]
        )
    }
}

extension Sequence where Element == LibraryEvent {
    /// The events these rows hold facts for.
    var events: [Event] { compactMap(\.facts) }
}

extension Sequence where Element == FollowedPerformer {
    var profiles: [PerformerProfile] { compactMap(\.profile) }
}

extension Sequence where Element == Event {
    /// What the reader went to: the library's own past.
    ///
    /// Keeping an event is what says they mean to go, so an event still in the
    /// library once its date has passed is one they went to. Nothing else is
    /// recorded, and nothing else needs to be — an event they did not go to is
    /// one they take out.
    var attended: [Event] { filter { !$0.isUpcoming } }

    /// Upcoming first, soonest first, and then the past, most recent first —
    /// the order the favourites are listed in, the same the library uses.
    func upcomingFirst() -> [Event] {
        let upcoming = filter(\.isUpcoming).sorted { $0.sortDate < $1.sortDate }
        let past = filter { !$0.isUpcoming }.sorted { $0.sortDate > $1.sortDate }
        return upcoming + past
    }
}

extension EventGroup {
    /// One list broken down the way the toolbar says: the half the filter
    /// picks, grouped by month or by the billed artist.
    static func groups(of pool: some Sequence<Event>, filter: LibraryFilter,
                       grouping: Grouping) -> [EventGroup] {
        let events = filter.rows(of: pool)
        switch grouping {
        case .date:
            return byMonth(events)
        case .artist:
            var buckets: [String: [Event]] = [:]
            for event in events { buckets[event.artist, default: []].append(event) }
            return buckets
                .map { EventGroup(id: $0.key, label: $0.key, events: $0.value) }
                // Busiest artist first, then alphabetically so the order is stable.
                .sorted { ($0.events.count, $1.label) > ($1.events.count, $0.label) }
        }
    }
}
