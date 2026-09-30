import Foundation

/// Where an event stands at one moment — what the event sheet's timeline says
/// and how far along its doors, start and end the night has got.
///
/// Worked out from the event's instants rather than from the clock it is
/// printed on, so it is right on either setting of ``TimeDisplay``. Computed
/// for a moment it is handed, which is what lets the sheet redraw it every
/// second and the tests pin it to one.
nonisolated struct EventProgress: Equatable {
    enum Phase: Equatable {
        /// A day still to come, counted as ``Event/daysAway`` counts it.
        case ahead(days: Int)
        /// On the day, with nothing published to count down to.
        case today
        /// On the day, before the doors.
        case beforeDoors(opening: Date)
        /// On the day, before the start, where no doors time was published.
        case beforeShow(starting: Date)
        /// The doors are open and the show has not started.
        case doorsOpen(showStarts: Date)
        /// The show is on. The end is nil where the page published none.
        case onNow(ends: Date?)
        /// Over, and still the same day.
        case wrapped
        /// The day is over.
        case over
    }

    let phase: Phase
    /// How far along the night it has got: 0 at the doors, ½ at the start, 1
    /// at the end — so each half is the share of that stretch gone by, which
    /// is what the sheet fills the line between its two times with.
    let fraction: Double

    init(event: Event, at now: Date) {
        let times = Event.inOrder(event.doorsOpen, event.startsAt, event.endsAt)

        // Asked first, and of the event's own times rather than of its day: a
        // show that runs past midnight is still on after its day is over.
        if let starts = times.starts {
            let ends = times.ends.flatMap { $0 > starts ? $0 : nil }
            // An event with no end published is given the length the calendar
            // entry gets, so the line has somewhere to run to — the sheet still
            // prints no end time.
            let runsTo = ends ?? starts.addingTimeInterval(Event.assumedLength)
            if now >= starts, now < runsTo {
                phase = .onNow(ends: ends)
                fraction = 0.5 + 0.5 * now.timeIntervalSince(starts) / runsTo.timeIntervalSince(starts)
                return
            }
            if let doors = times.doors, doors < starts, now >= doors, now < starts {
                phase = .doorsOpen(showStarts: starts)
                fraction = 0.5 * now.timeIntervalSince(doors) / starts.timeIntervalSince(doors)
                return
            }
            if now >= runsTo {
                phase = event.dayEnds > now ? .wrapped : .over
                fraction = 1
                return
            }
        }

        guard event.dayEnds > now else {
            phase = .over
            fraction = 1
            return
        }
        let reader = Calendar.current
        let days = reader.dateComponents([.day], from: reader.startOfDay(for: now),
                                         to: reader.startOfDay(for: event.localDay)).day ?? 0
        if days > 0 {
            phase = .ahead(days: days)
        } else if let doors = times.doors, now < doors {
            phase = .beforeDoors(opening: doors)
        } else if let starts = times.starts, now < starts {
            phase = .beforeShow(starting: starts)
        } else {
            phase = .today
        }
        fraction = 0
    }

    /// Whether the line is moving now — the doors open or the show on — which
    /// is when the sheet draws a marker where it has got to.
    var isUnderway: Bool {
        switch phase {
        case .doorsOpen, .onNow: true
        default: false
        }
    }

    /// Whether this is the day itself, when what the card says changes by the
    /// minute rather than by the day.
    var isToday: Bool {
        switch phase {
        case .ahead, .over: false
        default: true
        }
    }
}
