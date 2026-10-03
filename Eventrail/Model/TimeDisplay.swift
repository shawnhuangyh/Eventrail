import SwiftUI

/// Which clock an event's day and times are shown on: the hall's, as
/// Eventernote's members wrote them, or the reader's own.
///
/// Per-device, in `UserDefaults` and deliberately not synced, like
/// ``Appearance``: the reader's own clock is this device's clock, and a phone
/// that travels with them has not asked for the iPad at home to follow it.
///
/// Only what is *shown* moves. Every instant behind it is the same either way —
/// the calendar entry, its door alert and the library's order are made of those
/// already — and so is everything that works in written dates: the month a row
/// is grouped under, the days-away count, the Following tab's date filter. A
/// night belongs to the day its hall says it falls on.
enum TimeDisplay: String, CaseIterable, Identifiable {
    case venue, local

    /// The `UserDefaults` key, read through `@AppStorage` by Settings and by
    /// every view that prints a day or a time.
    static let storageKey = "timeDisplay"

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .venue: "Venue Time"
        case .local: "Local Time"
        }
    }

    /// The same, short enough for the switch on an event's timeline card.
    var shortLabel: LocalizedStringKey {
        switch self {
        case .venue: "Venue"
        case .local: "Local"
        }
    }
}

nonisolated extension Event {
    /// This event as it is to be *printed* on `display`'s clock — never stored,
    /// never handed to the store, only formatted.
    ///
    /// On the reader's clock the day is the day of the first time the page
    /// published, in the reader's zone: 18:00 in Tokyo is 02:00 the same day in
    /// Los Angeles, and 09:00 the next morning nowhere. A night with no time
    /// published yet keeps its hall's day, because a day alone cannot be
    /// converted — its midnight in Tokyo is the afternoon before in London, and
    /// saying so would put the show on a day nobody announced.
    func shown(on display: TimeDisplay) -> Event {
        guard display == .local, let anchor = doorsOpen ?? startsAt ?? endsAt else { return self }
        var event = self
        event.date = anchor
        event.timeZone = .current
        return event
    }
}
