import Foundation

/// One thing a ticket still asks of the reader — apply by a day, pay by a
/// day, pick the ticket up from a day — on the Ticket To-Dos card on the Me
/// tab and the screen behind it (``TicketTodosView``), as the design's Ticket
/// To-Dos row draws them.
///
/// **Nothing here is kept**: a to-do is the reminders the reader wrote for the
/// ticket sale on a kept event (``ReminderKind/tickets``), read back. An
/// application deadline is a to-do of its own; a payment deadline and the
/// pickup after it are one, the ticket moving through them — Awaiting Payment,
/// Paid, Issued. Reaching a step is a date on its reminder
/// (``EventReminder/done``), which is also what stops that reminder's
/// notification, so the list, the event's own card and the notifications
/// cannot disagree.
///
/// `tracking` is handed over rather than the store, as ``LotteryList`` takes
/// it, so the whole of this stays `nonisolated` and testable.
nonisolated struct TicketTodo: Identifiable, Hashable, Sendable {
    let event: Event
    /// The deadline to apply by, where this is one — then the other two are nil.
    let application: EventReminder?
    let payment: EventReminder?
    let pickup: EventReminder?
    /// The round it is for: the one its reminders name, or the event's one
    /// win where they name none.
    let entry: LotteryEntry?
    /// What one ticket costs, where the reader wrote it on Ticket Details.
    let cost: Money?

    var id: String { "\(event.id)/\((application ?? payment ?? pickup)?.id.uuidString ?? "")" }

    /// Which of the three chips a to-do falls under: what it asks for next,
    /// or what it last asked for once it is done.
    nonisolated enum Kind: CaseIterable, Identifiable, Sendable {
        case apply, pay, pickUp

        var id: Self { self }
    }

    /// Where it stands.
    nonisolated enum State: Hashable, Sendable {
        case notApplied, applied
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
        /// The reminder that stands for it, where one does.
        let reminder: EventReminder?

        var id: State { name }
    }

    var state: State {
        if let application { return application.done == nil ? .notApplied : .applied }
        if payment?.missed == true || pickup?.missed == true { return .notPaid }
        if let pickup, pickup.done != nil { return .issued }
        if let payment { return payment.done == nil ? .awaitingPayment : .paid }
        return .awaitingPickup
    }

    /// The reminder of the step being waited on, or nil once nothing is.
    var current: EventReminder? {
        switch state {
        case .notApplied: application
        case .awaitingPayment: payment
        case .paid, .awaitingPickup: pickup
        case .applied, .issued, .notPaid: nil
        }
    }

    var isDone: Bool { current == nil }

    var kind: Kind {
        if application != nil { return .apply }
        switch state {
        case .awaitingPayment, .notPaid: return .pay
        case .paid: return pickup == nil ? .pay : .pickUp
        default: return .pickUp
        }
    }

    /// Every reminder it is made of, in the order they are reached.
    var reminders: [EventReminder] { [application, payment, pickup].compactMap { $0 } }

    /// The steps in order: those behind it done, the one it stands on now,
    /// the rest ahead.
    var steps: [Step] {
        let names: [(State, EventReminder?)]
        let reached: Int
        if application != nil {
            names = [(.notApplied, application), (.applied, nil)]
            reached = state == .applied ? 2 : 0
        } else if state == .notPaid {
            names = [(.awaitingPayment, payment), (.notPaid, nil)]
            reached = 2
        } else if payment != nil {
            names = [(.awaitingPayment, payment), (.paid, nil)] + (pickup == nil ? [] : [(.issued, pickup)])
            reached = switch state {
            case .awaitingPayment: 0
            case .paid: 2
            default: 3
            }
        } else {
            names = [(.awaitingPickup, pickup), (.issued, nil)]
            reached = state == .issued ? 2 : 0
        }
        return names.enumerated().map { index, step in
            Step(name: step.0, status: index < reached ? .done : index == reached ? .now : .ahead,
                 reminder: step.1)
        }
    }

    /// The moment the step being waited on falls on, on the hall's clock.
    var due: Date? { current.map { $0.date(in: event.timeZone) } }

    /// When the last step was reached, where it is done.
    var finished: Date? { isDone ? reminders.compactMap(\.done).max() : nil }

    /// How many of its reminders the reader's marks have stopped: those dealt
    /// with that had a notification to come.
    var stoppedReminders: Int { reminders.count { $0.done != nil && $0.lead != nil } }

    /// How long before a deadline it is drawn in red, and counted on the Me
    /// tab's badge.
    static let urgency: TimeInterval = 72 * 3600

    /// Whether a deadline — to apply, to pay — is under ``urgency`` away, or
    /// past. A pickup only opens, and can wait.
    func isUrgent(at now: Date = .now) -> Bool {
        guard kind != .pickUp, let due else { return false }
        return due.timeIntervalSince(now) < Self.urgency
    }

    /// What is to be paid: as the payment says, or the cost of one ticket by
    /// how many the round was won with.
    var total: Money? {
        if let owed = payment?.owed { return owed }
        guard let cost, let quantity = entry?.wonChoice?.quantity else { return nil }
        return Money(amount: cost.amount * Decimal(quantity), currency: cost.currency)
    }

    /// Where the page for it opens: the step waited on first, then any of them.
    var link: URL? { current?.link ?? reminders.compactMap(\.link).first }

    /// Where it is paid, or the ticket issued.
    var place: String? { current?.payAt ?? reminders.compactMap(\.payAt).first }
}

// MARK: - Moving along

nonisolated extension TicketTodo {
    /// The record with the step being waited on reached: applied, paid, or
    /// issued. Applying for a lottery round nothing is written for yet writes
    /// its entry too, pending, since that is what having applied is.
    func advanced(in record: Tracking, at now: Date = .now) -> Tracking {
        guard let current else { return record }
        var record = record.marking([current.id], done: now)
        if state == .notApplied, let round = current.round, !round.isEmpty,
           LotteryRound(rawValue: round)?.isFirstCome != true,
           !record.lotteries.contains(where: { $0.round == round }) {
            record.lotteries.append(LotteryEntry(round: round))
        }
        return record
    }

    /// The record with the last step taken back, one at a time: issued to
    /// paid, paid to awaiting payment. A round written by applying stays.
    func steppedBack(in record: Tracking) -> Tracking {
        switch state {
        case .applied: record.marking(Set(reminders.map(\.id)), done: nil)
        case .notPaid: record.marking(Set(reminders.filter { $0.missed == true }.map(\.id)), done: nil)
        case .issued: record.marking(pickup.map { [$0.id] } ?? [], done: nil)
        case .paid: record.marking(payment.map { [$0.id] } ?? [], done: nil)
        case .notApplied, .awaitingPayment, .awaitingPickup: record
        }
    }

    /// The record with the payment given up: neither it nor the pickup after
    /// it has anything left to say.
    func givenUp(in record: Tracking, at now: Date = .now) -> Tracking {
        guard state == .awaitingPayment else { return record }
        return record.marking(Set(reminders.map(\.id)), done: now, missed: true)
    }

    /// The record with the ticket stood at `state` — from Ticket Details,
    /// which picks where it stands rather than stepping there. Every step
    /// before it is reached, each keeping the date it had; every one after is
    /// taken back.
    func standing(at state: State, in record: Tracking, at now: Date = .now) -> Tracking {
        var record = record.marking(Set(reminders.filter { $0.missed == true }.map(\.id)), done: nil)
        let reached: (payment: Bool, pickup: Bool) = switch state {
        case .paid: (true, false)
        case .issued: (true, true)
        default: (false, false)
        }
        for (reminder, isReached) in [(payment, reached.payment), (pickup, reached.pickup)] {
            guard let reminder, (reminder.done != nil && reminder.missed != true) != isReached else { continue }
            record = record.marking([reminder.id], done: isReached ? now : nil)
        }
        return record
    }
}

nonisolated extension Tracking {
    /// This, with each of those reminders dealt with at `done` — or, with no
    /// date, to do again.
    func marking(_ ids: Set<EventReminder.ID>, done: Date?, missed: Bool = false) -> Tracking {
        var record = self
        for index in record.reminders.indices where ids.contains(record.reminders[index].id) {
            record.reminders[index].done = done
            record.reminders[index].missed = done != nil && missed ? true : nil
        }
        return record
    }

    /// The round a reminder is for, where it names one this record holds.
    func entry(for reminder: EventReminder) -> LotteryEntry? {
        guard let round = reminder.round, !round.isEmpty else { return nil }
        return lotteries.first { $0.round == round }
    }

    /// Whether `reminder` still has anything to say: not once it is dealt
    /// with, and not a payment or a pickup for a round that was lost, which
    /// has nothing to pay for. What a notification and a to-do both ask.
    func owes(_ reminder: EventReminder) -> Bool {
        guard reminder.done == nil else { return false }
        guard let kind = reminder.ticketKind, kind != .applicationDeadline else { return true }
        return entry(for: reminder)?.outcome != .lost
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

    /// One event's to-dos: each application deadline, then its payments and
    /// pickups paired off round by round, in the order they fall.
    static func todos(for event: Event, tracking: Tracking) -> [TicketTodo] {
        // A step dealt with stays, to be read under Done; one for a round
        // lost since has nothing to ask.
        let listed = tracking.reminders.filter { $0.ticketKind != nil && ($0.done != nil || tracking.owes($0)) }
        guard !listed.isEmpty else { return [] }
        let wins = tracking.lotteries.filter(\.isWon)

        var todos = listed.filter { $0.ticketKind == .applicationDeadline }.map {
            TicketTodo(event: event, application: $0, payment: nil, pickup: nil,
                       entry: tracking.entry(for: $0), cost: nil)
        }
        var rounds: [String] = []
        for reminder in listed where reminder.ticketKind != .applicationDeadline {
            let round = reminder.round ?? ""
            if !rounds.contains(round) { rounds.append(round) }
        }
        for round in rounds {
            let ofRound = listed.filter { ($0.round ?? "") == round }
            let payments = ofRound.filter { $0.ticketKind == .paymentDeadline }
            let pickups = ofRound.filter { $0.ticketKind == .ticketPickup }
            let entry = round.isEmpty ? (wins.count == 1 ? wins.first : nil)
                : tracking.lotteries.first { $0.round == round }
            for index in 0 ..< max(payments.count, pickups.count) {
                todos.append(TicketTodo(event: event, application: nil,
                                        payment: index < payments.count ? payments[index] : nil,
                                        pickup: index < pickups.count ? pickups[index] : nil,
                                        entry: entry, cost: tracking.price))
            }
        }
        return todos
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

    /// How many reminders the done ones stopped between them.
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
