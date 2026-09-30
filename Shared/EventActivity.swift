import ActivityKit
import Foundation

/// A Live Activity for one event the reader holds a ticket for: on the Lock
/// Screen and in the Dynamic Island from two hours before its doors until the
/// show is over, as `Eventrail v3.dc.html` draws it.
///
/// Compiled into the app, which starts, schedules, updates and ends it, and
/// into the widget extension, which draws it. What never changes over the
/// night is here; the times and the seat are in ``ContentState``, since the
/// page can publish a door time — and the reader write a seat — after the
/// activity was asked for.
nonisolated struct EventActivityAttributes: ActivityAttributes {
    let eventID: String
    let title: String
    let venue: String
    /// The event's Eventernote page. Tapping the activity opens the app on
    /// the event's sheet with it.
    let link: URL
    /// When the activity was set to come on: the window's opening, or the
    /// moment it was asked for where that was already inside it. Kept so the
    /// app can tell that a door time published since has moved the window.
    let opens: Date

    struct ContentState: Codable, Hashable, Sendable {
        /// Where the night stood when the app last looked — see
        /// ``shownStage(isStale:)`` for what is drawn once that has passed.
        var stage: EventActivityStage
        var doors: Date?
        var starts: Date
        /// The published end, nil where the page published none.
        var ends: Date?
        /// Where the show runs to: its published end, or the app's assumed
        /// length after the start — see `Event.assumedLength`.
        var runsTo: Date
        /// The clock the times are printed on: the hall's, or the reader's
        /// where Settings says so — the same one the event's sheet prints.
        var timeZone: TimeZone
        var seat: String
    }
}

/// Where a night stands, as the activity shows it. Each has its own words and
/// colour, and the fill runs over the times on either side of it.
nonisolated enum EventActivityStage: String, Codable, Hashable, Sendable {
    /// Before the doors, which the page published.
    case beforeDoors
    /// Before the start, where the page published no doors.
    case beforeShow
    case doorsOpen
    /// The last few minutes before the start — see ``soonBeforeStart``.
    case startingSoon
    case onNow
    /// Over. The app ends the activity as soon as it next runs.
    case wrapped

    /// How long before the doors the activity comes on.
    static let lead: TimeInterval = 2 * 60 * 60

    /// How close to the start "Doors open" turns into "Starting in", as it
    /// does on the event's sheet.
    static let soonBeforeStart: TimeInterval = 5 * 60

    /// Where a night with these times stands at `now`.
    static func at(_ now: Date, doors: Date?, starts: Date, runsTo: Date) -> Self {
        if now >= runsTo { return .wrapped }
        if now >= starts { return .onNow }
        guard let doors, doors < starts else { return .beforeShow }
        if now < doors { return .beforeDoors }
        return starts.timeIntervalSince(now) <= soonBeforeStart ? .startingSoon : .doorsOpen
    }

    /// The stage this one gives way to.
    ///
    /// Doors open goes straight on to the show: the last few minutes before
    /// the start are only ever shown by the app looking, since the one change
    /// an activity can make by itself is better spent on the start.
    var following: Self {
        switch self {
        case .beforeDoors: .doorsOpen
        case .beforeShow, .doorsOpen, .startingSoon: .onNow
        case .onNow, .wrapped: .wrapped
        }
    }
}

nonisolated extension EventActivityAttributes.ContentState {
    /// The times it was made from, read at `now`.
    func stage(at now: Date) -> EventActivityStage {
        .at(now, doors: doors, starts: starts, runsTo: runsTo)
    }

    /// When ``stage`` gives way to ``EventActivityStage/following`` — the
    /// activity's stale date.
    ///
    /// A Live Activity is drawn again only when the app sends it something,
    /// and the app is rarely running during a concert. What the system does
    /// by itself is mark an activity stale at the date it was given, and draw
    /// it again saying so; that is spent on the next change of stage, so the
    /// activity moves on at least once with nobody looking.
    var staleDate: Date? {
        switch stage {
        case .beforeDoors: doors
        case .beforeShow, .doorsOpen, .startingSoon: starts
        case .onNow: runsTo
        case .wrapped: nil
        }
    }

    /// The next moment worth the app waking for: the stale date, and the
    /// start of "Starting in" before it.
    var nextChange: Date? {
        if stage == .doorsOpen { return starts.addingTimeInterval(-EventActivityStage.soonBeforeStart) }
        return staleDate
    }

    /// What the activity draws: the stage it was last sent, or the one after
    /// it once its stale date has passed.
    func shownStage(isStale: Bool) -> EventActivityStage {
        isStale ? stage.following : stage
    }
}

nonisolated extension EventActivityAttributes {
    /// The container the app and the extension share. The flyer is written
    /// there by the app, since the extension cannot download anything as it
    /// draws.
    static let appGroup = "group.moe.shawn.Eventrail"

    /// Where the flyer for `eventID` is kept while its activity lasts, sized
    /// for the largest place the activity draws it.
    static func posterFile(for eventID: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "LiveActivity", directoryHint: .isDirectory)
            .appending(path: "\(eventID).jpg", directoryHint: .notDirectory)
    }
}
