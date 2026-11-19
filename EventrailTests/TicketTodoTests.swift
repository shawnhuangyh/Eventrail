import Foundation
import Testing
import UserNotifications
@testable import Eventrail

/// What a ticket still asks of the reader, read off the rounds won — see
/// ``TicketTodo``, ``TicketTodoList`` and ``TicketStageAlert``.
@MainActor
struct TicketTodoTests {
    /// The design's own afternoon: Wednesday, November 11, 2026, 17:42 in Tokyo.
    let now = Fixtures.date(2026, 11, 11, 17, 42)
    let show = Fixtures.event(id: "liella", date: Fixtures.date(2026, 11, 28))
    let tour = Fixtures.event(id: "tour", date: Fixtures.date(2027, 3, 20))

    static func moment(_ month: Int, _ day: Int, at minute: Int? = nil) -> TicketMoment {
        TicketMoment(day: CalendarDay(year: 2026, month: month, day: day), minute: minute)
    }

    /// A ticket won in the second lottery, to be paid for by the 13th and
    /// picked up from noon on the 19th.
    static let seats = LotteryChoice(seatClass: "A席", quantity: 2)
    static let wonRound: LotteryEntry = {
        var entry = LotteryEntry(round: LotteryRound.second.rawValue, choices: [seats], result: .won(seats.id))
        entry.payment = moment(11, 13)
        entry.pickup = moment(11, 19, at: 12 * 60)
        return entry
    }()

    let won = Tracking(cost: 8800, lotteries: [wonRound])

    func todos(_ record: Tracking, for event: Event? = nil) -> [TicketTodo] {
        TicketTodoList.todos(for: event ?? show, tracking: record)
    }

    func row(_ entry: LotteryEntry, for event: Event? = nil) -> LotteryRow {
        LotteryRow(event: event ?? show, entry: entry)
    }

    // MARK: - What is a to-do

    /// A round won with a step written; not one waiting or lost, and not a
    /// win with nothing to pay or pick up.
    @Test func onlyARoundWonWithAStepIsAToDo() {
        var waiting = Self.wonRound
        waiting.result = .pending
        var lost = Self.wonRound
        lost.result = .lost
        var bare = Self.wonRound
        bare.payment = nil
        bare.pickup = nil
        #expect(todos(Tracking(lotteries: [waiting])).isEmpty)
        #expect(todos(Tracking(lotteries: [lost])).isEmpty)
        #expect(todos(Tracking(lotteries: [bare])).isEmpty)
        #expect(todos(won).count == 1)
    }

    /// A first-come round is got by being written, and paid for like a win.
    @Test func aFirstComeRoundPaysAsAWinDoes() throws {
        var bought = LotteryEntry(round: LotteryRound.generalSale.rawValue, choices: [LotteryChoice()])
        bought.payment = Self.moment(11, 13)
        let ticket = try #require(todos(Tracking(lotteries: [bought])).first)
        #expect(ticket.kind == .pay)
    }

    @Test func aPaymentAndItsPickupAreOneTicket() throws {
        let ticket = try #require(todos(won).first)
        #expect(ticket.state == .awaitingPayment)
        #expect(ticket.kind == .pay)
        #expect(ticket.steps.map(\.name) == [.awaitingPayment, .paid, .issued])
        #expect(ticket.steps.map(\.status) == [.now, .ahead, .ahead])
        // A day alone closes at 23:59 on the hall's clock.
        #expect(ticket.due == Fixtures.date(2026, 11, 13, 23, 59))
    }

    /// A pickup's day alone opens in the morning.
    @Test func aPickupsDayAloneOpensInTheMorning() {
        var entry = Self.wonRound
        entry.pickup = Self.moment(11, 19)
        #expect(entry.date(of: .pickup, in: Fixtures.tokyo) == Fixtures.date(2026, 11, 19, 10))
        #expect(entry.date(of: .payment, in: Fixtures.tokyo) == Fixtures.date(2026, 11, 13, 23, 59))
    }

    /// The cost of one ticket by how many were won is what is to be paid.
    @Test func theTotalIsTheCostByTheTicketsWon() throws {
        let ticket = try #require(todos(won).first)
        #expect(ticket.total == Money(amount: 17600, currency: Currencies.yen))
    }

    @Test func anAmountWrittenOnThePaymentStandsOverTheSum() throws {
        var record = won
        record.lotteries[0].payment?.owed = Money(amount: 18260, currency: "JPY")
        #expect(try #require(todos(record).first).total?.amount == 18260)
    }

    /// As it is kept: text, so nothing is rounded through a `Double`; and
    /// every field left out where nothing is written.
    @Test func aStepComesBackAsItWasWritten() throws {
        var entry = Self.wonRound
        entry.payment?.owed = Money(amount: Decimal(string: "49.99")!, currency: "USD")
        entry.payment?.payAt = "クレジットカード"
        entry.payment?.link = URL(string: "https://eplus.jp/")
        entry.payment?.done = now
        let text = LotteryEntry.rowText(of: entry)
        #expect(LotteryEntry.entry(inRow: text) == entry)

        let bare = LotteryEntry.rowText(of: LotteryEntry(round: "最速先行抽選", payment: Self.moment(11, 13)))
        #expect(bare.contains(#""payment":{"day":"2026-11-13"}"#))
    }

    /// A step this build cannot read costs the step, not the round.
    @Test func aStepItCannotReadCostsOnlyTheStep() throws {
        let text = #"{"applications":1,"id":"5A0B8C1E-7C11-4B7B-9D51-2F0E3C8A1B22","payment":{"minute":5},"result":"pending","round":"最速先行抽選"}"#
        let entry = try #require(LotteryEntry.entry(inRow: text))
        #expect(entry.payment == nil)
        #expect(entry.round == "最速先行抽選")
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

    @Test func notPayingInTimeStopsEveryStepAndLeavesTheResult() throws {
        let lapsed = try #require(todos(won).first).givenUp(in: won, at: now)
        let ticket = try #require(todos(lapsed).first)
        #expect(ticket.state == .notPaid)
        #expect(ticket.isDone)
        #expect(lapsed.lotteries[0].payment?.done == now && lapsed.lotteries[0].pickup?.done == now)
        #expect(lapsed.lotteries[0].result == won.lotteries[0].result)
        #expect(ticket.steppedBack(in: lapsed) == won)
    }

    /// From Ticket Details, which picks where the ticket stands.
    @Test func standingAtAStepReachesEveryStepBeforeIt() throws {
        let ticket = try #require(todos(won).first)
        let issued = ticket.standing(at: .issued, in: won, at: now)
        #expect(issued.lotteries[0].payment?.done == now && issued.lotteries[0].pickup?.done == now)
        let back = try #require(todos(issued).first).standing(at: .awaitingPayment, in: issued, at: now)
        #expect(back == won)
        // A step already reached keeps the date it was reached on.
        let later = now.addingTimeInterval(3600)
        let paid = ticket.standing(at: .paid, in: won, at: now)
        let then = try #require(todos(paid).first).standing(at: .issued, in: paid, at: later)
        #expect(then.lotteries[0].payment?.done == now)
        #expect(then.lotteries[0].pickup?.done == later)
    }

    // MARK: - The notification

    @Test func aStepReachedOwesNoNotification() throws {
        let rows = [row(Self.wonRound)]
        #expect(TicketStageAlert.due(in: rows, paymentLead: 24 * 60, at: now).map(\.stage) == [.payment, .pickup])
        let paid = try #require(todos(won).first).advanced(in: won, at: now)
        let owed = TicketStageAlert.due(in: [row(paid.lotteries[0])], paymentLead: 24 * 60, at: now)
        #expect(owed.map(\.stage) == [.pickup])
        #expect(TicketStageAlert.standing(in: [row(paid.lotteries[0])])
            == [TicketStageAlert.identifier(of: .pickup, of: Self.wonRound.id, at: show.id)])
    }

    /// A payment as long ahead as Settings says, or not at all; a pickup as
    /// it opens.
    @Test func aPaymentComesAsFarAheadAsSettingsSays() throws {
        let rows = [row(Self.wonRound)]
        let payment = try #require(TicketStageAlert.due(in: rows, paymentLead: 24 * 60, at: now).first)
        #expect(payment.date == Fixtures.date(2026, 11, 12, 23, 59))
        #expect(payment.request.content.interruptionLevel == .active)
        let urgent = try #require(TicketStageAlert.due(in: rows, paymentLead: 60, at: now).first)
        #expect(urgent.request.content.interruptionLevel == .timeSensitive)
        let none = TicketStageAlert.due(in: rows, paymentLead: nil, at: now)
        #expect(none.map(\.stage) == [.pickup])
        #expect(none.first?.date == Fixtures.date(2026, 11, 19, 12))
        #expect(none.first?.request.content.interruptionLevel == .active)
    }

    @Test func aLostRoundIsOwedNothing() {
        var lost = Self.wonRound
        lost.result = .lost
        #expect(TicketStageAlert.due(in: [row(lost)], paymentLead: 24 * 60, at: now).isEmpty)
        #expect(TicketStageAlert.standing(in: [row(lost)]).isEmpty)
    }

    /// Every round won on the events, a first-come round's included.
    @Test func theRoundsWonIncludeAFirstComeOne() {
        var bought = LotteryEntry(round: LotteryRound.generalSale.rawValue, choices: [LotteryChoice()])
        bought.payment = Self.moment(11, 13)
        let waiting = LotteryEntry(round: LotteryRound.earliest.rawValue)
        let rows = TicketStageAlert.rows(in: [show]) { _ in Tracking(lotteries: [bought, waiting, Self.wonRound]) }
        #expect(rows.map(\.entry.id) == [bought.id, Self.wonRound.id])
    }

    @Test func aTicketsNotificationCarriesItsButtonAndWhatIsOwed() throws {
        var entry = Self.wonRound
        entry.payment?.owed = Money(amount: 17600, currency: "JPY")
        entry.payment?.payAt = "セブン-イレブン"
        let alert = try #require(TicketStageAlert(row(entry), stage: .payment, lead: 24 * 60, at: now))
        let request = alert.request
        #expect(request.content.categoryIdentifier == TicketStageAlert.category(of: .payment, linked: false))
        #expect(alert.body.hasSuffix("· セブン-イレブン"))
        #expect(alert.body.contains("17,600"))
        #expect(alert.body.contains(LotteryRound.label(of: entry.round)))
        // Read by the delegate as a results-day reminder is: the round's page.
        #expect(request.content.userInfo[LotteryReminder.eventKey] as? String == show.id)
        #expect(request.content.userInfo[LotteryReminder.entryKey] as? String == entry.id.uuidString)
        #expect(request.content.userInfo[TicketStageAlert.stageKey] as? String == "payment")

        entry.payment?.link = URL(string: "https://eplus.jp/")
        let linked = try #require(TicketStageAlert(row(entry), stage: .payment, lead: 24 * 60, at: now))
        #expect(linked.request.content.categoryIdentifier == TicketStageAlert.category(of: .payment, linked: true))
        #expect(linked.request.content.userInfo[TicketStageAlert.linkKey] as? String == "https://eplus.jp/")
    }

    /// A scheduled copy is left alone; another moment, page or lead is not.
    @Test func aScheduledCopyIsKnownByItsMomentWordsAndButtons() throws {
        var entry = Self.wonRound
        entry.payment = TicketMoment(day: CalendarDay(Fixtures.day(fromToday: 5), in: .gregorian(in: Fixtures.tokyo)))
        let alert = try #require(TicketStageAlert(row(entry), stage: .payment, lead: 24 * 60))
        #expect(alert.isScheduled(as: alert.request))
        #expect(!alert.isScheduled(as: nil))
        let sooner = try #require(TicketStageAlert(row(entry), stage: .payment, lead: 60))
        #expect(!sooner.isScheduled(as: alert.request))
        entry.payment?.link = URL(string: "https://eplus.jp/")
        let linked = try #require(TicketStageAlert(row(entry), stage: .payment, lead: 24 * 60))
        #expect(!linked.isScheduled(as: alert.request))
    }

    /// Shared with the results days and the deadlines, under their one limit.
    @Test func theStepsShareTheLotteriesLimit() {
        let due = LotteryAlert.due(in: LotteryList(events: [show]) { _ in self.won },
                                   won: [row(Self.wonRound)], deadlineLead: 24 * 60, asOf: now)
        #expect(due.count == 2)
        #expect(due.allSatisfy { LotteryAlert.isOwn($0.identifier) })
    }

    // MARK: - The list

    @Test func theListRunsSoonestFirstAndCutsByHowFarOff() throws {
        var later = Self.wonRound
        later.id = UUID()
        later.round = LotteryRound.first.rawValue
        later.payment = Self.moment(11, 15)
        later.pickup = nil
        var latest = later
        latest.id = UUID()
        latest.round = LotteryRound.earliest.rawValue
        latest.payment = Self.moment(12, 7)
        let records = ["liella": won, "tour": Tracking(lotteries: [later, latest])]
        let list = TicketTodoList(events: [tour, show], at: now) { records[$0.id] ?? Tracking() }
        #expect(list.open.map(\.event.id) == ["liella", "tour", "tour"])
        #expect(list.groups(of: nil, at: now).map(\.bucket) == [.dueSoon, .thisWeek, .later])
        #expect(list.groups(of: .pay, at: now).map(\.todos.count) == [1, 1, 1])
        // Only the first payment is under three days off.
        #expect(list.urgent(at: now).map(\.event.id) == ["liella"])
        #expect(list.done.isEmpty)
    }

    /// A pickup only opens: it is never what the badge counts.
    @Test func aPickupIsNeverUrgent() throws {
        var entry = Self.wonRound
        entry.payment = nil
        entry.pickup = Self.moment(11, 12, at: 12 * 60)
        let ticket = try #require(todos(Tracking(lotteries: [entry])).first)
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
        #expect(undone.lotteries == won.lotteries)
    }
}
