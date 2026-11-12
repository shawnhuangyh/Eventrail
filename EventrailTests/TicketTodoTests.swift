import Foundation
import Testing
import UserNotifications
@testable import Eventrail

/// What a ticket still asks of the reader, read off an event's reminders —
/// see ``TicketTodo`` and ``TicketTodoList``.
@MainActor
struct TicketTodoTests {
    /// The design's own afternoon: Wednesday, November 11, 2026, 17:42 in Tokyo.
    let now = Fixtures.date(2026, 11, 11, 17, 42)
    let show = Fixtures.event(id: "liella", date: Fixtures.date(2026, 11, 28))
    let tour = Fixtures.event(id: "tour", date: Fixtures.date(2027, 3, 20))

    static func reminder(_ kind: ReminderKind, _ month: Int, _ day: Int, at minute: Int = 23 * 60 + 59,
                         round: String? = nil) -> EventReminder {
        var reminder = EventReminder(title: kind.rawValue, day: CalendarDay(year: 2026, month: month, day: day),
                                     minute: minute, lead: kind.defaultLead)
        reminder.round = round
        return reminder
    }

    func reminder(_ kind: ReminderKind, _ month: Int, _ day: Int, at minute: Int = 23 * 60 + 59,
                  round: String? = nil) -> EventReminder {
        Self.reminder(kind, month, day, at: minute, round: round)
    }

    /// A ticket won in the second lottery, to be paid for by the 13th and
    /// picked up from the 19th. Made once: every reminder has an id of its own.
    let won: Tracking = {
        let seats = LotteryChoice(seatClass: "A席", quantity: 2)
        return Tracking(cost: 8800, lotteries: [LotteryEntry(round: LotteryRound.second.rawValue, choices: [seats],
                                                               result: .won(seats.id))],
                        reminders: [reminder(.paymentDeadline, 11, 13), reminder(.ticketPickup, 11, 19, at: 12 * 60)])
    }()

    func todos(_ record: Tracking, for event: Event? = nil) -> [TicketTodo] {
        TicketTodoList.todos(for: event ?? show, tracking: record)
    }

    // MARK: - What is a to-do

    @Test func onlyTheTicketSalesTimesAreToDos() {
        let record = Tracking(reminders: [reminder(.goodsSale, 11, 28), reminder(.applicationDeadline, 11, 15)])
        #expect(todos(record).map(\.kind) == [.apply])
    }

    @Test func aPaymentAndItsPickupAreOneTicket() throws {
        let ticket = try #require(todos(won).first)
        #expect(todos(won).count == 1)
        #expect(ticket.state == .awaitingPayment)
        #expect(ticket.kind == .pay)
        #expect(ticket.steps.map(\.name) == [.awaitingPayment, .paid, .issued])
        #expect(ticket.steps.map(\.status) == [.now, .ahead, .ahead])
        #expect(ticket.due == Fixtures.date(2026, 11, 13, 23, 59))
    }

    /// The event's one win answers for deadlines that name no round, and the
    /// cost of one ticket by how many were won is what is to be paid.
    @Test func theTotalIsTheCostByTheTicketsWon() throws {
        let ticket = try #require(todos(won).first)
        #expect(ticket.entry?.round == LotteryRound.second.rawValue)
        #expect(ticket.total == Money(amount: 17600, currency: Currencies.yen))
    }

    @Test func anAmountWrittenOnThePaymentStandsOverTheSum() throws {
        var record = won
        record.reminders[0].owed = Money(amount: 18260, currency: "JPY")
        #expect(try #require(todos(record).first).total?.amount == 18260)
    }

    /// As it is kept: text, so nothing is rounded through a `Double`.
    @Test func anAmountComesBackAsItWasWritten() throws {
        var written = reminder(.paymentDeadline, 11, 13)
        written.owed = Money(amount: Decimal(string: "49.99")!, currency: "USD")
        let read = try JSONDecoder().decode(EventReminder.self, from: JSONEncoder().encode(written))
        #expect(read.owed == Money(amount: Decimal(string: "49.99")!, currency: "USD"))
        #expect(read == written)
    }

    /// A reminder written before any of this reads back, and is written back,
    /// as it was — or every device would send every reminder again.
    @Test func aReminderFromBeforeReadsAndWritesAsItWas() throws {
        let old = #"{"day":"2026-11-13","id":"0B7C6E0E-8C56-4D5B-9A32-1D2F3A4B5C6D","lead":1440,"minute":1439,"title":"入金締切"}"#
        let read = try JSONDecoder().decode(EventReminder.self, from: Data(old.utf8))
        #expect(read.done == nil && read.round == nil && read.owed == nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(String(decoding: try encoder.encode(read), as: UTF8.self) == old)
    }

    // MARK: - Moving along

    @Test func payingMovesTheTicketOnToItsPickup() throws {
        let paid = try #require(todos(won).first).advanced(in: won, at: now)
        let ticket = try #require(todos(paid).first)
        #expect(ticket.state == .paid)
        #expect(ticket.kind == .pickUp)
        #expect(ticket.steps.map(\.status) == [.done, .done, .now])
        #expect(ticket.due == Fixtures.date(2026, 11, 19, 12))
        #expect(!ticket.isDone)
        #expect(ticket.stoppedReminders == 1)

        let issued = ticket.advanced(in: paid, at: now)
        let held = try #require(todos(issued).first)
        #expect(held.state == .issued)
        #expect(held.isDone)
        #expect(held.finished == now)
        #expect(held.stoppedReminders == 2)
    }

    @Test func aStepIsTakenBackOneAtATime() throws {
        let paid = try #require(todos(won).first).advanced(in: won, at: now)
        let issued = try #require(todos(paid).first).advanced(in: paid, at: now)
        let back = try #require(todos(issued).first).steppedBack(in: issued)
        #expect(try #require(todos(back).first).state == .paid)
        let again = try #require(todos(back).first).steppedBack(in: back)
        #expect(again == won)
    }

    @Test func notPayingInTimeStopsEveryReminderAndLeavesTheRound() throws {
        let lapsed = try #require(todos(won).first).givenUp(in: won, at: now)
        let ticket = try #require(todos(lapsed).first)
        #expect(ticket.state == .notPaid)
        #expect(ticket.isDone)
        #expect(lapsed.reminders.allSatisfy { !lapsed.owes($0) })
        #expect(lapsed.lotteries == won.lotteries)
        #expect(ticket.steppedBack(in: lapsed) == won)
    }

    /// From Ticket Details, which picks where the ticket stands.
    @Test func standingAtAStepReachesEveryStepBeforeIt() throws {
        let ticket = try #require(todos(won).first)
        let issued = ticket.standing(at: .issued, in: won, at: now)
        #expect(issued.reminders.allSatisfy { $0.done == now })
        let back = try #require(todos(issued).first).standing(at: .awaitingPayment, in: issued, at: now)
        #expect(back == won)
        // A step already reached keeps the date it was reached on.
        let later = now.addingTimeInterval(3600)
        let paid = ticket.standing(at: .paid, in: won, at: now)
        let then = try #require(todos(paid).first).standing(at: .issued, in: paid, at: later)
        #expect(then.reminders.map(\.done) == [now, later])
    }

    @Test func applyingWritesTheRoundToWaitForItsResults() throws {
        let record = Tracking(reminders: [reminder(.applicationDeadline, 11, 15, round: LotteryRound.earliest.rawValue)])
        let applied = try #require(todos(record, for: tour).first).advanced(in: record, at: now)
        #expect(applied.lotteries.map(\.round) == [LotteryRound.earliest.rawValue])
        #expect(applied.lotteries.first?.isPending == true)
        let todo = try #require(todos(applied, for: tour).first)
        #expect(todo.state == .applied && todo.isDone)
        // Taken back, the round stays: it may have been written to since.
        #expect(todo.steppedBack(in: applied).lotteries == applied.lotteries)
    }

    @Test func applyingForARoundAlreadyWrittenAddsNoSecond() throws {
        let round = LotteryRound.first.rawValue
        let record = Tracking(lotteries: [LotteryEntry(round: round, applications: 3)],
                              reminders: [reminder(.applicationDeadline, 11, 15, round: round)])
        let applied = try #require(todos(record, for: tour).first).advanced(in: record, at: now)
        #expect(applied.lotteries == record.lotteries)
    }

    // MARK: - What a lost round leaves

    @Test func aLostRoundHasNothingToPayFor() {
        let round = LotteryRound.first.rawValue
        let record = Tracking(lotteries: [LotteryEntry(round: round, result: .lost)],
                              reminders: [reminder(.paymentDeadline, 11, 13, round: round)])
        #expect(todos(record).isEmpty)
        #expect(!record.owes(record.reminders[0]))
        #expect(ReminderAlert.due(in: [show], tracking: { _ in record }, at: now).isEmpty)
    }

    // MARK: - The notification

    @Test func aStepReachedOwesNoNotification() throws {
        #expect(ReminderAlert.due(in: [show], tracking: { _ in self.won }, at: now).count == 2)
        let paid = try #require(todos(won).first).advanced(in: won, at: now)
        let owed = ReminderAlert.due(in: [show], tracking: { _ in paid }, at: now)
        #expect(owed.map(\.reminderID) == [won.reminders[1].id])
    }

    @Test func aTicketsNotificationCarriesItsButtonAndWhatIsOwed() throws {
        var payment = reminder(.paymentDeadline, 11, 13)
        payment.owed = Money(amount: 17600, currency: "JPY")
        payment.payAt = "セブン-イレブン"
        let alert = try #require(ReminderAlert(reminder: payment, event: show, at: now))
        #expect(alert.category == ReminderAlert.category(of: .paymentDeadline, linked: false))
        #expect(alert.body.hasSuffix("· セブン-イレブン"))
        #expect(alert.body.contains("17,600"))
        payment.link = URL(string: "https://eplus.jp/")
        let linked = try #require(ReminderAlert(reminder: payment, event: show, at: now))
        #expect(linked.category == ReminderAlert.category(of: .paymentDeadline, linked: true))
        #expect(linked.request.content.userInfo[ReminderAlert.linkKey] as? String == "https://eplus.jp/")
        // A time at the goods sale has no step to mark.
        let sale = try #require(ReminderAlert(reminder: reminder(.goodsSale, 11, 28, at: 12 * 60), event: show, at: now))
        #expect(sale.category == nil)
    }

    // MARK: - The list

    @Test func theListRunsSoonestFirstAndCutsByHowFarOff() throws {
        let apply = Tracking(reminders: [reminder(.applicationDeadline, 11, 15), reminder(.applicationDeadline, 12, 7)])
        let records = ["liella": won, "tour": apply]
        let list = TicketTodoList(events: [tour, show], at: now) { records[$0.id] ?? Tracking() }
        #expect(list.open.map(\.kind) == [.pay, .apply, .apply])
        #expect(list.groups(of: nil, at: now).map(\.bucket) == [.dueSoon, .thisWeek, .later])
        #expect(list.groups(of: .apply, at: now).map(\.todos.count) == [1, 1])
        // Only the payment is under three days off.
        #expect(list.urgent(at: now).map(\.event.id) == ["liella"])
        #expect(list.done.isEmpty)
    }

    /// A pickup only opens: it is never what the badge counts.
    @Test func aPickupIsNeverUrgent() throws {
        let record = Tracking(reminders: [reminder(.ticketPickup, 11, 12, at: 12 * 60)])
        let ticket = try #require(todos(record).first)
        #expect(ticket.state == .awaitingPickup)
        #expect(ticket.steps.map(\.name) == [.awaitingPickup, .issued])
        #expect(!ticket.isUrgent(at: now))
    }

    @Test func anEventGoneByLeavesToDoAndKeepsDone() throws {
        let after = Fixtures.date(2026, 12, 1)
        let paid = try #require(todos(won).first).advanced(in: won, at: now)
        let issued = try #require(todos(paid).first).advanced(in: paid, at: now)
        #expect(TicketTodoList(events: [show], at: after) { _ in self.won }.open.isEmpty)
        let list = TicketTodoList(events: [show], at: after) { _ in issued }
        #expect(list.done.count == 1)
        #expect(list.stoppedReminders == 2)
        #expect(list.doneByMonth(in: .gregorian(in: Fixtures.tokyo)).map(\.todos.count) == [1])
    }

    // MARK: - Taking a mark back

    /// Laid over the record as it stands, so a note written meanwhile stays.
    @Test func undoingLeavesWhatWasWrittenMeanwhile() throws {
        let paid = try #require(todos(won).first).advanced(in: won, at: now)
        var meanwhile = paid
        meanwhile.note = "row 12"
        let undone = meanwhile.applying(changesFrom: paid, to: won)
        #expect(undone.note == "row 12")
        #expect(undone.reminders == won.reminders)
    }
}
