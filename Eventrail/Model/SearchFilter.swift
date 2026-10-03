import Foundation
import SwiftUI

/// What the Search tab's event results are narrowed to: whether an event is
/// still ahead, and the part of the world.
///
/// Answered in two places, because the site answers only half of it. An area
/// is Eventernote's own: its search takes an `area_id`, one at a time, and
/// counts what it found — so an area is asked of the site and the total over
/// the results stays the site's. Ahead or past is held here instead, over the
/// pages read, since the site's search knows nothing of "upcoming".
///
/// What is held here leans on the listing being in date order, whichever way
/// round the reader asked for it (``SearchOrder``): the rows wanted are one
/// unbroken run of it, on one side of today. So the pages wholly in front of
/// that run are skipped rather than read — see
/// ``comesBeforeMatches(_:reading:)`` — and the reading stops at the first row
/// past it — see ``comesAfterMatches(_:reading:)``.
struct SearchFilter: Hashable {
    /// Whether an event is still ahead.
    enum When: CaseIterable, Hashable {
        case any, upcoming, past

        var label: LocalizedStringKey {
            switch self {
            case .any: "All"
            case .upcoming: "Upcoming"
            case .past: "Past"
            }
        }
    }

    /// One of the site's areas.
    ///
    /// Abroad is offered here, unlike in ``Region``, because here it is the
    /// site that files a hall abroad: 海外 is its sixth `area_id`, and nothing
    /// in the app reads it off an address.
    enum Area: Hashable {
        case region(Region)
        case overseas

        static var all: [Area] { Region.allCases.map(Area.region) + [.overseas] }

        var areaID: Int {
            switch self {
            case .region(let region): region.areaID
            case .overseas: 6
            }
        }

        var label: LocalizedStringKey {
            switch self {
            case .region(let region): region.label
            case .overseas: "Overseas"
            }
        }
    }

    var when: When = .any
    /// The one area the site is asked for, or nil for anywhere.
    var area: Area?

    var isNarrowing: Bool { when != .any || area != nil }

    /// Whether rows are held back here, over the pages read, rather than by
    /// the site — so a count of what is shown is not the site's total.
    var holdsRows: Bool { when != .any }

    /// Whether a row the site sent survives what is held here.
    func matches(_ event: Event) -> Bool {
        switch when {
        case .any: true
        case .upcoming: event.isUpcoming
        case .past: !event.isUpcoming
        }
    }

    /// Whether, in a listing read in `order`, the rows the filter wants have
    /// not begun yet at `event` — so a page ending on it can be skipped: a
    /// event still ahead while only past ones are wanted, newest first, or a
    /// past one while only upcoming ones are, oldest first.
    func comesBeforeMatches(_ event: Event, reading order: SearchOrder) -> Bool {
        switch (when, order) {
        case (.past, .newestFirst): event.isUpcoming
        case (.upcoming, .oldestFirst): !event.isUpcoming
        default: false
        }
    }

    /// Whether, in a listing read in `order`, nothing from `event` on can
    /// match — so the reading can stop: the other way round.
    func comesAfterMatches(_ event: Event, reading order: SearchOrder) -> Bool {
        switch (when, order) {
        case (.upcoming, .newestFirst): !event.isUpcoming
        case (.past, .oldestFirst): event.isUpcoming
        default: false
        }
    }

    /// What the filter holds a list to, in as few words as will say it: when,
    /// and where — "All" while it holds nothing back. The face of the capsule
    /// over every list it narrows.
    var summary: Text {
        var parts: [Text] = []
        if when != .any { parts.append(Text(when.label)) }
        if let area { parts.append(Text(area.label)) }
        guard let first = parts.first else { return Text("All") }
        return parts.dropFirst().reduce(first) { Text("\($0) · \($1)") }
    }
}

/// Which way round the Search tab's event results run: by date, the newest or
/// the oldest first. Asked of the site, which sorts the whole listing rather
/// than the page in hand.
///
/// As `sort=event_date` and `order`, not as the `sort_by` its search page's
/// menu is named: the page's own script splits the menu's "event_date,ASC"
/// into those two before asking, and `sort_by` sent as it stands is ignored —
/// the site answers newest first whatever it says.
nonisolated enum SearchOrder: Hashable, CaseIterable, Sendable {
    case newestFirst, oldestFirst

    /// The value of the site's own `order` field.
    var order: String {
        switch self {
        case .newestFirst: "DESC"
        case .oldestFirst: "ASC"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .newestFirst: "Newest First"
        case .oldestFirst: "Oldest First"
        }
    }

    var systemImage: String {
        switch self {
        case .newestFirst: "arrow.down"
        case .oldestFirst: "arrow.up"
        }
    }
}
