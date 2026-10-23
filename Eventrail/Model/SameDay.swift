import Foundation

/// Two events the reader keeps on one day, and whether both can be made — what
/// the Same Day card on an event's sheet and the mark on a My Events row read.
///
/// Read off the published times alone. The later one has to start no sooner
/// than the earlier one is over, and — at two halls — no sooner than the
/// reader can get from the one to the other, which Apple Maps answers (see
/// ``TravelTimes``). The time to be there by is the start, 開演, not the
/// doors: a second show of the day is made by arriving after its doors.
///
/// An end the page never published is ``Event/assumedLength`` after the start,
/// as the calendar entry and the timeline card assume. Most pages publish
/// none, so most overlaps are ones the times only suggest — and say so.
nonisolated struct SameDay: Hashable, Sendable {
    /// The one that starts first, and the one after it — by start, or by day
    /// and then by id where either has none.
    let earlier: Event
    let later: Event

    init(_ one: Event, _ other: Event) {
        let first = switch (Self.span(of: one), Self.span(of: other)) {
        case let (a?, b?) where a.starts != b.starts: a.starts < b.starts
        default: (one.sortDate, one.id) < (other.sortDate, other.id)
        }
        (earlier, later) = first ? (one, other) : (other, one)
    }

    /// The other of the two.
    func other(than event: Event) -> Event {
        earlier.id == event.id ? later : earlier
    }

    // MARK: - The hours

    /// When an event starts and when it is over, as far as the page says.
    struct Span: Hashable, Sendable {
        let starts: Date
        let ends: Date
        /// Whether ``ends`` is only ``Event/assumedLength`` after the start,
        /// for want of a published end.
        let endIsAssumed: Bool
    }

    /// Nil where no start is published. An end before the start is the next
    /// morning (``Event/inOrder(_:_:_:)``); one past
    /// ``PassportStats/longestEvent`` is a typo rather than a show, and is
    /// assumed instead, as the Passport reads it.
    static func span(of event: Event) -> Span? {
        let times = Event.inOrder(event.doorsOpen, event.startsAt, event.endsAt)
        guard let starts = times.starts else { return nil }
        if let ends = times.ends, ends > starts,
           ends.timeIntervalSince(starts) <= PassportStats.longestEvent {
            return Span(starts: starts, ends: ends, endIsAssumed: false)
        }
        return Span(starts: starts, ends: starts.addingTimeInterval(Event.assumedLength), endIsAssumed: true)
    }

    enum Timing: Hashable, Sendable {
        /// One or the other has no published start, so nothing can be said of
        /// the hours yet.
        case untimed
        /// The later one starts this long before the earlier one is over —
        /// `endIsAssumed` where that end is only assumed.
        case overlapping(by: TimeInterval, endIsAssumed: Bool)
        /// The later one starts this long after the earlier one ends, at the
        /// same hall: nowhere to get to.
        case sameHall(gap: TimeInterval)
        /// The same, at two halls — or where either is no hall at all, a
        /// stream or a room nobody has named (``Event/isAtHall``).
        case apart(gap: TimeInterval)
    }

    var timing: Timing {
        guard let first = Self.span(of: earlier), let second = Self.span(of: later) else {
            return .untimed
        }
        if second.starts < first.ends {
            let overlap = min(first.ends, second.ends).timeIntervalSince(second.starts)
            return .overlapping(by: overlap, endIsAssumed: first.endIsAssumed)
        }
        let gap = second.starts.timeIntervalSince(first.ends)
        return isSameHall ? .sameHall(gap: gap) : .apart(gap: gap)
    }

    /// By the name the page prints, as a hall is asked about by its name.
    var isSameHall: Bool {
        earlier.isAtHall && earlier.venue == later.venue
    }

    /// Whether there is a journey to ask Maps about: two halls, with time
    /// between the two shows.
    var needsTravel: Bool {
        guard case .apart = timing else { return false }
        return earlier.isAtHall && later.isAtHall
    }

    /// When the reader sets off — the earlier one's end, published or
    /// assumed — which is what a timetable is read for.
    var departure: Date? { Self.span(of: earlier)?.ends }

    // MARK: - What a row marks

    /// Why the two cannot both be made, as far as is known: they overlap, or
    /// the journey between them takes longer than the time between them.
    enum Clash: Int, Hashable, Sendable, Comparable {
        case tightTransfer
        case overlap

        static func < (lhs: Clash, rhs: Clash) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// `travel` is how long the journey takes, where Maps has said; with no
    /// answer, only an overlap is a clash.
    func clash(travel: TimeInterval?) -> Clash? {
        switch timing {
        case .overlapping: .overlap
        case .apart(let gap) where needsTravel:
            if let travel, travel > gap { .tightTransfer } else { nil }
        default: nil
        }
    }

    // MARK: - Finding them

    /// Every other of `events` on the day `event` is on, paired with it, in
    /// the order the others start.
    ///
    /// The same day is the day each hall prints (``Event/localDay``), as
    /// every list in the app counts it.
    static func pairs(of event: Event, among events: some Sequence<Event>) -> [SameDay] {
        var seen: Set<Event.ID> = [event.id]
        return events
            .filter { $0.localDay == event.localDay && seen.insert($0.id).inserted }
            .map { SameDay(event, $0) }
            .sorted { ($0.other(than: event).sortDate, $0.other(than: event).id)
                < ($1.other(than: event).sortDate, $1.other(than: event).id) }
    }

    /// Every pair of `events` that share a day — for a whole list at once.
    static func pairs(in events: some Sequence<Event>) -> [SameDay] {
        var seen: Set<Event.ID> = []
        let days = Dictionary(grouping: events.filter { seen.insert($0.id).inserted }, by: \.localDay)
        return days.values.flatMap { day in
            day.indices.flatMap { index in
                day[(index + 1)...].map { SameDay(day[index], $0) }
            }
        }
    }

    /// The worst clash each of `events` has with another of them, for the
    /// ones that have any. `travel` is what Maps has already said of a
    /// journey, and asks nothing.
    static func clashes(
        in events: some Sequence<Event>, travel: (SameDay) -> TimeInterval?
    ) -> [Event.ID: Clash] {
        var clashes: [Event.ID: Clash] = [:]
        for pair in pairs(in: events) {
            guard let clash = pair.clash(travel: pair.needsTravel ? travel(pair) : nil) else { continue }
            for id in [pair.earlier.id, pair.later.id] {
                clashes[id] = max(clashes[id] ?? clash, clash)
            }
        }
        return clashes
    }
}
