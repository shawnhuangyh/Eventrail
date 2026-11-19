import Foundation

/// One thing a ticket still asks of the reader — pay for it by a day, pick it
/// up from a day — on the Ticket To-Dos card on the Me tab and the screen
/// behind it (``TicketTodosView``), as the design's Ticket To-Dos row draws
/// them.
///
/// **Nothing here is kept**: a to-do is a won round's payment and pickup
/// (``LotteryEntry/payment``, ``LotteryEntry/pickup``), read back — the ticket
/// moving through them, Awaiting Payment, Paid, Issued. Reaching a step is a
/// date on it (``TicketMoment/done``), which is also what stops its
/// notification (``TicketStageAlert``), so the list, the round's own page and
/// the notifications cannot disagree.
///
/// `tracking` is handed over rather than the store, as ``LotteryList`` takes
/// it, so the whole of this stays `nonisolated` and testable.
nonisolated struct TicketTodo: Identifiable, Hashable, Sendable {
    let event: Event
    /// The round won, which holds the steps.
    let entry: LotteryEntry
    /// What one ticket costs, where the reader wrote it on Ticket Details.
    let cost: Money?

    var id: String { "\(event.id)/\(entry.id.uuidString)" }

    var payment: TicketMoment? { entry.payment }
    var pickup: TicketMoment? { entry.pickup }

    /// Which of the two chips a to-do falls under: what it asks for next,
    /// or what it last asked for once it is done.
    nonisolated enum Kind: CaseIterable, Identifiable, Sendable {
        case pay, pickUp

        var id: Self { self }
    }

    /// Where it stands.
    nonisolated enum State: Hashable, Sendable {
        case awaitingPayment, paid
        /// A pickup with no payment written beside it, not yet issued.
        case awaitingPickup
        case issued
        /// The payment was not made in time, and the ticket let go.
        case notPaid
    }

    /// One step of the way, as the card's stepper and the sheet's timeline
    /// draw it.
    nonisolated struct Step: Identifiable, Hashable, Sendable {
        nonisolated enum Status: Sendable { case done, now, ahead }

        let name: State
        let status: Status
        /// The step of the round it stands for, where one does.
        let stage: TicketStage?

        var id: State { name }
    }

    var state: State {
        if payment?.missed == true || pickup?.missed == true { return .notPaid }
        if let pickup, pickup.done != nil { return .issued }
        if let payment { return payment.done == nil ? .awaitingPayment : .paid }
        return .awaitingPickup
    }

    /// The step being waited on, or nil once nothing is.
    var current: TicketStage? {
        switch state {
        case .awaitingPayment: .payment
        case .paid, .awaitingPickup: pickup == nil ? nil : .pickup
        case .issued, .notPaid: nil
        }
    }

    var isDone: Bool { current == nil }

    var kind: Kind {
        switch state {
        case .awaitingPayment, .notPaid: .pay
        case .paid: pickup == nil ? .pay : .pickUp
        default: .pickUp
        }
    }

    /// The steps written for it, in the order they are reached.
    var stages: [TicketStage] { TicketStage.allCases.filter { entry[$0] != nil } }

    /// The steps in order: those behind it done, the one it stands on now,
    /// the rest ahead.
    var steps: [Step] {
        let names: [(State, TicketStage?)]
        let reached: Int
        if state == .notPaid {
            names = [(.awaitingPayment, .payment), (.notPaid, nil)]
            reached = 2
        } else if payment != nil {
            names = [(.awaitingPayment, .payment), (.paid, nil)] + (pickup == nil ? [] : [(.issued, .pickup)])
            reached = switch state {
            case .awaitingPayment: 0
            case .paid: 2
            default: 3
            }
        } else {
            names = [(.awaitingPickup, .pickup), (.issued, nil)]
            reached = state == .issued ? 2 : 0
        }
        return names.enumerated().map { index, step in
            Step(name: step.0, status: index < reached ? .done : index == reached ? .now : .ahead, stage: step.1)
        }
    }

    /// The moment `stage` falls on, on the hall's clock.
    func date(of stage: TicketStage) -> Date? { entry.date(of: stage, in: event.timeZone) }

    /// The moment the step being waited on falls on.
    var due: Date? { current.flatMap(date(of:)) }

    /// When the last step was reached, where it is done.
    var finished: Date? { isDone ? stages.compactMap { entry[$0]?.done }.max() : nil }

    /// How many of its notifications the reader's marks have stopped: one
    /// for each step reached.
    var stoppedReminders: Int { stages.count { entry[$0]?.done != nil } }

    /// How long before a deadline it is drawn in red, and counted on the Me
    /// tab's badge.
    static let urgency: TimeInterval = 72 * 3600

    /// Whether a payment is under ``urgency`` away, or past. A pickup only
    /// opens, and can wait.
    func isUrgent(at now: Date = .now) -> Bool {
        guard kind == .pay, let due else { return false }
        return due.timeIntervalSince(now) < Self.urgency
    }

    /// What is to be paid: as the payment says, or the cost of one ticket by
    /// how many the round was won with.
    var total: Money? {
        if let owed = payment?.owed { return owed }
        guard let cost, let quantity = entry.wonChoice?.quantity else { return nil }
        return Money(amount: cost.amount * Decimal(quantity), currency: cost.currency)
    }

    /// Where the page for it opens: the step waited on first, then either.
    var link: URL? { current.flatMap { entry[$0]?.link } ?? stages.compactMap { entry[$0]?.link }.first }

    /// Where it is paid, or the ticket issued.
    var place: String? { current.flatMap { entry[$0]?.payAt } ?? stages.compactMap { entry[$0]?.payAt }.first }
}

// MARK: - Moving along

nonisolated extension TicketTodo {
    /// The record with the step being waited on reached: paid, or issued.
    func advanced(in record: Tracking, at now: Date = .now) -> Tracking {
        guard let current else { return record }
        return record.updatingLottery(entry.id) { $0[current]?.done = now }
    }

    /// The record with the last step taken back, one at a time: issued to
    /// paid, paid to awaiting payment.
    func steppedBack(in record: Tracking) -> Tracking {
        switch state {
        case .notPaid:
            record.updatingLottery(entry.id) { entry in
                for stage in TicketStage.allCases where entry[stage]?.missed == true {
                    entry[stage]?.done = nil
                    entry[stage]?.missed = nil
                }
            }
        case .issued: record.updatingLottery(entry.id) { $0.pickup?.done = nil }
        case .paid: record.updatingLottery(entry.id) { $0.payment?.done = nil }
        case .awaitingPayment, .awaitingPickup: record
        }
    }

    /// The record with the payment given up: neither it nor the pickup after
    /// it has anything left to say.
    func givenUp(in record: Tracking, at now: Date = .now) -> Tracking {
        guard state == .awaitingPayment else { return record }
        return record.updatingLottery(entry.id) { entry in
            for stage in TicketStage.allCases where entry[stage] != nil {
                entry[stage]?.done = now
                entry[stage]?.missed = true
            }
        }
    }

    /// The record with the ticket stood at `state` — from Ticket Details,
    /// which picks where it stands rather than stepping there. Every step
    /// before it is reached, each keeping the date it had; every one after is
    /// taken back.
    func standing(at state: State, in record: Tracking, at now: Date = .now) -> Tracking {
        let reached: (payment: Bool, pickup: Bool) = switch state {
        case .paid: (true, false)
        case .issued: (true, true)
        default: (false, false)
        }
        return record.updatingLottery(entry.id) { entry in
            for stage in TicketStage.allCases where entry[stage]?.missed == true {
                entry[stage]?.done = nil
                entry[stage]?.missed = nil
            }
            for (stage, isReached) in [(TicketStage.payment, reached.payment), (.pickup, reached.pickup)] {
                guard let moment = entry[stage], (moment.done != nil) != isReached else { continue }
                entry[stage]?.done = isReached ? now : nil
            }
        }
    }
}

nonisolated extension LotteryEntry {
    /// `stage` reached at `now`, and every step written before it: a ticket
    /// issued was paid for, as Ticket Details' Issued has it
    /// (``TicketTodo/standing(at:in:at:)``). What a notification's button
    /// marks (``LotteryReminders/markDone(_:of:at:)``), which can be pressed
    /// on any step, not only the one waited on. A step already reached keeps
    /// its date, and nothing after `stage` is taken back: a button pressed
    /// late, on a ticket since issued, leaves it issued.
    mutating func reach(_ stage: TicketStage, at now: Date = .now) {
        for step in TicketStage.allCases {
            if self[step] != nil, self[step]?.done == nil { self[step]?.done = now }
            if step == stage { break }
        }
    }

    /// The marks that took this round from `before` to `after` taken back:
    /// a step's ``TicketMoment/done`` and ``TicketMoment/missed`` alone, each
    /// only where the mark changed it and it still says what the mark wrote.
    /// What Undo does (``EventStore/take(back:)``), over the round as it now
    /// stands: a deadline, an amount or a page written meanwhile — here or
    /// on another device — stays, and so does a mark written over since.
    mutating func takeBack(marksFrom after: LotteryEntry, to before: LotteryEntry) {
        for stage in TicketStage.allCases where self[stage] != nil {
            if after[stage]?.done != before[stage]?.done, self[stage]?.done == after[stage]?.done {
                self[stage]?.done = before[stage]?.done
            }
            if after[stage]?.missed != before[stage]?.missed, self[stage]?.missed == after[stage]?.missed {
                self[stage]?.missed = before[stage]?.missed
            }
        }
    }
}

nonisolated extension Tracking {
    /// This, with the round `id` changed by `change` — and nothing, where no
    /// such round is here.
    func updatingLottery(_ id: LotteryEntry.ID, _ change: (inout LotteryEntry) -> Void) -> Tracking {
        var record = self
        guard let index = record.lotteries.firstIndex(where: { $0.id == id }) else { return record }
        change(&record.lotteries[index])
        return record
    }
}

// MARK: - The list

/// Every to-do across the library, as the Me card samples it and the screen
/// behind it lists it.
nonisolated struct TicketTodoList {
    /// Those still asking for something, for events still ahead, the soonest
    /// first.
    let open: [TicketTodo]
    /// Those dealt with, the latest first.
    let done: [TicketTodo]

    init(events: some Sequence<Event>, at now: Date = .now, tracking: (Event) -> Tracking) {
        var open: [TicketTodo] = [], done: [TicketTodo] = []
        for event in events {
            for todo in Self.todos(for: event, tracking: tracking(event)) {
                if todo.isDone {
                    done.append(todo)
                } else if event.dayEnds > now {
                    open.append(todo)
                }
            }
        }
        self.open = open.sorted {
            let left = $0.due ?? .distantFuture, right = $1.due ?? .distantFuture
            return left != right ? left < right : $0.id < $1.id
        }
        self.done = done.sorted {
            let left = $0.finished ?? .distantPast, right = $1.finished ?? .distantPast
            return left != right ? left > right : $0.id < $1.id
        }
    }

    /// One event's to-dos: each round won with a payment or a pickup written,
    /// in sale order. A round lost since, or set back to waiting, has
    /// nothing to ask; what it holds stays, should it be won again.
    static func todos(for event: Event, tracking: Tracking) -> [TicketTodo] {
        tracking.lotteriesInOrder
            .filter { $0.isWon && ($0.payment != nil || $0.pickup != nil) }
            .map { TicketTodo(event: event, entry: $0, cost: tracking.price) }
    }

    /// The to-do with this id as it now stands, in either half.
    func todo(_ id: TicketTodo.ID) -> TicketTodo? {
        open.first { $0.id == id } ?? done.first { $0.id == id }
    }

    /// The open ones under a chip, or all of them.
    func open(of kind: TicketTodo.Kind?) -> [TicketTodo] {
        kind.map { kind in open.filter { $0.kind == kind } } ?? open
    }

    /// The deadlines under ``TicketTodo/urgency`` away: what the Me tab's
    /// badge counts.
    func urgent(at now: Date = .now) -> [TicketTodo] {
        open.filter { $0.isUrgent(at: now) }
    }

    /// How many notifications the done ones stopped between them.
    var stoppedReminders: Int { done.reduce(0) { $0 + $1.stoppedReminders } }

    /// How far off a group of open to-dos is.
    nonisolated enum Bucket: Hashable, Sendable {
        /// Under ``TicketTodo/urgency`` away, or past.
        case dueSoon
        /// Within seven days.
        case thisWeek
        case later

        init(due: Date?, at now: Date) {
            let away = (due ?? .distantFuture).timeIntervalSince(now)
            self = away < TicketTodo.urgency ? .dueSoon : away < 7 * 24 * 3600 ? .thisWeek : .later
        }
    }

    /// The open ones under a chip, cut by how far off they are.
    func groups(of kind: TicketTodo.Kind?, at now: Date = .now) -> [(bucket: Bucket, todos: [TicketTodo])] {
        let shown = open(of: kind)
        return [Bucket.dueSoon, .thisWeek, .later].compactMap { bucket in
            let todos = shown.filter { Bucket(due: $0.due, at: now) == bucket }
            return todos.isEmpty ? nil : (bucket, todos)
        }
    }

    /// The done ones by the month they were finished in, on `calendar`.
    func doneByMonth(in calendar: Calendar = .gregorian()) -> [(month: Date, todos: [TicketTodo])] {
        var months: [Date] = []
        var buckets: [Date: [TicketTodo]] = [:]
        for todo in done {
            let finished = todo.finished ?? .distantPast
            let month = calendar.dateInterval(of: .month, for: finished)?.start ?? finished
            if buckets[month] == nil { months.append(month) }
            buckets[month, default: []].append(todo)
        }
        return months.map { ($0, buckets[$0] ?? []) }
    }
}
