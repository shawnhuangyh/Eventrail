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
        /// ``phases(at:)`` for what is drawn after it.
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

/// One stretch of the night as the activity draws it: a stage, from the
/// moment it comes on until the moment the next one does.
nonisolated struct EventActivityPhase: Hashable, Sendable {
    let stage: EventActivityStage
    /// When it comes on — nil for the first, already under way.
    var from: Date?
    /// When it gives way — nil for the last.
    var until: Date?
}

nonisolated extension EventActivityAttributes.ContentState {
    /// The times it was made from, read at `now`.
    func stage(at now: Date) -> EventActivityStage {
        .at(now, doors: doors, starts: starts, runsTo: runsTo)
    }

    /// The rest of the night from ``stage`` on — or from where it stands at
    /// `now`, where that is further on — each stage with its stretch.
    ///
    /// A Live Activity is drawn again only when the app sends it something,
    /// and the app is rarely running during a concert. So the extension draws
    /// every stage still to come at once and shows each only inside its own
    /// stretch, switched by the system as the night runs on — see
    /// `EventLiveActivity`.
    func phases(at now: Date? = nil) -> [EventActivityPhase] {
        var first = stage
        if let now, stage(at: now).order > first.order { first = stage(at: now) }
        let moments = [doors, starts.addingTimeInterval(-EventActivityStage.soonBeforeStart), starts, runsTo]
            .compactMap(\.self)
            .sorted()
        var phases = [EventActivityPhase(stage: first)]
        for moment in moments {
            let next = stage(at: moment)
            guard next.order > phases[phases.count - 1].stage.order else { continue }
            phases[phases.count - 1].until = moment
            phases.append(EventActivityPhase(stage: next, from: moment))
        }
        return phases
    }

    /// When ``stage`` gives way to the next — the activity's stale date, and
    /// when the app next brings it up to date.
    ///
    /// The system draws an activity again as it goes stale, which catches up
    /// anything the stretches did not: whatever is drawn then starts from
    /// where the night stands.
    var nextChange: Date? {
        phases().first?.until
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
