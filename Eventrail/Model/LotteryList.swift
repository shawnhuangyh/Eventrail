import SwiftUI

/// Every lottery round entered for an event still ahead, as one list — the
/// Lotteries card on the Me tab and the screen behind it (``LotteriesView``),
/// as `Eventrail v4.dc.html` §8a draws them.
///
/// Read off the same record the ticket sheet writes (``Tracking/lotteries``),
/// so nothing here is kept: a result recorded from the list is the round's
/// own, and the ticket sheet opens on it.
///
/// Lottery rounds alone (``LotteryEntry/isLottery``): a first-come round is a
/// seat got rather than a draw waiting on anything, and a ticket carried over
/// from before entries has no round to wait for. An event whose day is over
/// leaves the list — what its lotteries came to is the Passport's.
///
/// `tracking` is a closure rather than the store, as ``PassportStats`` takes
/// it, so the whole type stays `nonisolated` and testable.
nonisolated struct LotteryList {
    let rows: [LotteryRow]

    init(events: some Sequence<Event>, tracking: (Event) -> Tracking) {
        rows = events.filter(\.isUpcoming).flatMap { event in
            tracking(event).lotteries.filter(\.isLottery).map { LotteryRow(event: event, entry: $0) }
        }
    }

    /// The rounds on one half of the screen.
    func rows(in half: LotteryHalf) -> [LotteryRow] {
        rows.filter { half.holds($0.entry) }
    }

    /// The rounds still waiting, by the day their results come out — the
    /// soonest first, so a day already gone leads — and a round with no day
    /// written after every one with a day. What the Me card samples.
    var next: [LotteryRow] {
        rows(in: .awaiting).sorted(by: LotteryRow.byResultsDay)
    }

    /// One half, broken up the way the capsule says.
    ///
    /// Waiting rounds by results day lead with the ones whose day has come
    /// (``LotteryRow/isResultsOut(asOf:)``) — the ones with a result to write
    /// down — then go by the month the results are out, and end on the ones
    /// with no day; by event date, they go by the month of the event. Decided
    /// rounds are the won and then the rest, in either order.
    func groups(in half: LotteryHalf, by order: LotteryOrder, asOf now: Date = .now) -> [LotteryGroup] {
        let sorted = rows(in: half).sorted(by: order == .resultsDay ? LotteryRow.byResultsDay : LotteryRow.byEventDate)
        switch (half, order) {
        case (.awaiting, .resultsDay):
            return LotteryGroup.bucketed(sorted) { row in
                guard let day = row.entry.day else { return .noDay }
                return row.isResultsOut(asOf: now) ? .resultsOut : .month(day.monthGroupLabel)
            }
        case (.awaiting, .eventDate):
            return LotteryGroup.bucketed(sorted) { .month($0.event.monthGroupLabel) }
        case (.decided, _):
            return [LotteryGroup(kind: .won, rows: sorted.filter(\.entry.isWon)),
                    LotteryGroup(kind: .notWon, rows: sorted.filter { !$0.entry.isWon })]
                .filter { !$0.rows.isEmpty }
        }
    }
}

/// One round, and the event it was entered for.
nonisolated struct LotteryRow: Identifiable, Hashable {
    let event: Event
    let entry: LotteryEntry

    var id: String { "\(event.id)/\(entry.id)" }

    /// Whether the round is still waiting and its results day has come —
    /// today included, since results out today can be in already. What the
    /// list puts first and the Me card fills its tile for.
    func isResultsOut(asOf now: Date = .now) -> Bool {
        guard entry.isPending, let day = entry.day else { return false }
        return day.daysAway(from: now) <= 0
    }

    /// The results day, soonest first and no day last, then the event.
    static func byResultsDay(_ lhs: LotteryRow, _ rhs: LotteryRow) -> Bool {
        switch (lhs.entry.day, rhs.entry.day) {
        case let (left?, right?) where left != right: return left < right
        case (.some, nil): return true
        case (nil, .some): return false
        default: return byEvent(lhs, rhs)
        }
    }

    /// The event, soonest first, then the results day.
    static func byEventDate(_ lhs: LotteryRow, _ rhs: LotteryRow) -> Bool {
        guard lhs.event.sortDate == rhs.event.sortDate, lhs.event.id == rhs.event.id else {
            return byEvent(lhs, rhs)
        }
        switch (lhs.entry.day, rhs.entry.day) {
        case let (left?, right?) where left != right: return left < right
        case (.some, nil): return true
        case (nil, .some): return false
        default: return byRound(lhs, rhs)
        }
    }

    /// The event, then the order the sale runs its rounds in.
    private static func byEvent(_ lhs: LotteryRow, _ rhs: LotteryRow) -> Bool {
        if lhs.event.sortDate != rhs.event.sortDate { return lhs.event.sortDate < rhs.event.sortDate }
        if lhs.event.id != rhs.event.id { return lhs.event.id < rhs.event.id }
        return byRound(lhs, rhs)
    }

    private static func byRound(_ lhs: LotteryRow, _ rhs: LotteryRow) -> Bool {
        LotteryRound.order(of: lhs.entry.round) < LotteryRound.order(of: rhs.entry.round)
    }
}

/// A run of rounds under one header.
nonisolated struct LotteryGroup: Identifiable {
    let kind: Kind
    let rows: [LotteryRow]

    var id: Kind { kind }

    nonisolated enum Kind: Hashable {
        /// Waiting, with the results day come.
        case resultsOut
        /// A month, as the list's months are written.
        case month(String)
        /// Waiting, with no results day written down.
        case noDay
        case won
        /// Lost, or drawn with no win — anything decided but a win.
        case notWon
    }

    /// Rows already in order, cut wherever the header they fall under changes.
    static func bucketed(_ rows: [LotteryRow], by kind: (LotteryRow) -> Kind) -> [LotteryGroup] {
        var order: [Kind] = []
        var buckets: [Kind: [LotteryRow]] = [:]
        for row in rows {
            let key = kind(row)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(row)
        }
        return order.map { LotteryGroup(kind: $0, rows: buckets[$0] ?? []) }
    }
}

/// Which half of the Lotteries screen is on screen: the rounds still waiting
/// on a result, or the ones with one.
nonisolated enum LotteryHalf: CaseIterable, Identifiable {
    case awaiting, decided

    var id: Self { self }

    /// The half's name, with how many rounds it holds.
    func label(count: Int) -> Text {
        switch self {
        case .awaiting: Text("Awaiting · \(count)")
        case .decided: Text("Decided · \(count)")
        }
    }

    func holds(_ entry: LotteryEntry) -> Bool {
        switch self {
        case .awaiting: entry.isPending
        case .decided: !entry.isPending
        }
    }
}

/// How the Lotteries screen is put in order — the capsule at its foot.
nonisolated enum LotteryOrder: CaseIterable, Identifiable {
    case resultsDay, eventDate

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .resultsDay: "Results Day"
        case .eventDate: "Event Date"
        }
    }

    var symbol: String {
        switch self {
        case .resultsDay: "calendar.badge.clock"
        case .eventDate: "music.mic"
        }
    }
}

nonisolated extension CalendarDay {
    /// The month the day falls in, as the list's months are headed —
    /// "OCTOBER 2026", as ``Event/monthGroupLabel`` writes an event's.
    var monthGroupLabel: String {
        date().formatted(.dateTime.month(.wide).year()).localizedUppercase
    }
}

nonisolated extension LotteryEntry {
    /// Whether a result can be given yet: not while the results day written
    /// down is still to come, since nothing has been drawn to win or lose.
    /// Pending can always be given.
    func canBeDrawn(asOf now: Date = .now) -> Bool {
        (day?.daysAway(from: now) ?? 0) <= 0
    }
}

nonisolated extension Tracking {
    /// The record with one lottery's result given — from the Lotteries list,
    /// which records a result without opening the ticket sheet — and the
    /// ticket's class settled from the rounds as the sheet settles it on
    /// saving (``settleSeatClass(since:)``). The same record where there is no
    /// such lottery.
    func givingResult(_ result: LotteryResult, toLottery id: LotteryEntry.ID) -> Tracking {
        guard let index = lotteries.firstIndex(where: { $0.id == id }) else { return self }
        var record = self
        record.lotteries[index].result = result
        record.settleSeatClass(since: self)
        return record
    }

    /// Whether going from `earlier` to this took the ticket away — its last
    /// win taken out, or put back to Pending or Lost — with a seat or a cost
    /// still written for it. The two are asked only once there is a ticket,
    /// so kept, they would be kept out of sight; whoever takes the ticket
    /// away asks whether to clear them too.
    func leavesSeatOrCostBehind(since earlier: Tracking) -> Bool {
        earlier.hasTicket && !hasTicket && (!seat.isEmpty || cost != nil)
    }

    /// This, with the seat and the cost cleared.
    var clearingSeatAndCost: Tracking {
        var record = self
        record.seat = ""
        record.cost = nil
        record.currency = ""
        return record
    }
}
