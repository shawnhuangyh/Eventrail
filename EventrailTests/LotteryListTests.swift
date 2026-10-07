import Foundation
import Testing
@testable import Eventrail

struct LotteryListTests {
    /// A results day `offset` days from the reader's today.
    static func day(_ offset: Int) -> CalendarDay {
        CalendarDay(Calendar.current.date(byAdding: .day, value: offset, to: .now)!)
    }

    static let soon = Fixtures.event(id: "soon", date: Fixtures.day(fromToday: 20))
    static let later = Fixtures.event(id: "later", date: Fixtures.day(fromToday: 90))
    static let gone = Fixtures.event(id: "gone", date: Fixtures.day(fromToday: -3))

    static let sChoice = LotteryChoice(seatClass: "S席", quantity: 2)

    static let records: [Event.ID: Tracking] = [
        "soon": Tracking(lotteries: [
            LotteryEntry(round: "最速先行抽選", applications: 3, day: day(-2), choices: [sChoice]),
            LotteryEntry(round: "プレイガイド先行", day: day(5)),
            // First come, first served: a seat got, not a draw.
            LotteryEntry(round: "一般発売", choices: [LotteryChoice()]),
        ]),
        "later": Tracking(lotteries: [
            LotteryEntry(round: "最速先行抽選", day: day(-10), result: .lost),
            LotteryEntry(round: "プレイガイド先行", day: day(-1), result: .won(nil)),
            LotteryEntry(round: "プレイガイド二次先行"),
            LotteryEntry(round: "最速先行抽選", day: day(0)),
            // A ticket carried over from before entries: no round to wait on.
            .ticketHeld,
        ]),
        "gone": Tracking(lotteries: [LotteryEntry(round: "最速先行抽選", day: day(-20))]),
    ]

    let list = LotteryList(events: [Self.soon, Self.later, Self.gone]) {
        Self.records[$0.id] ?? Tracking()
    }

    @Test func listsTheLotteryRoundsOfEventsStillAhead() {
        #expect(list.rows.count == 6)
        #expect(!list.rows.contains { $0.event.id == "gone" })
        #expect(!list.rows.contains { $0.entry.isFirstCome })
        #expect(!list.rows.contains { $0.entry.id == LotteryEntry.carriedOverTicketID })
    }

    @Test func aCountCarriedOverIsAWaitingLottery() {
        let carried = LotteryList(events: [Self.soon]) { _ in
            Tracking(lotteries: LotteryEntry.carriedOver(count: 4))
        }
        #expect(carried.rows.map(\.entry.applications) == [4])
        #expect(carried.rows(in: .awaiting).count == 1)
    }

    @Test func theHalvesAreAwaitingAndDecided() {
        #expect(list.rows(in: .awaiting).count == 4)
        #expect(list.rows(in: .decided).map(\.entry.isWon) == [false, true])
    }

    @Test func waitingByResultsDayLeadsWithTheOnesOut() {
        let groups = list.groups(in: .awaiting, by: .resultsDay)
        #expect(groups.first?.kind == .resultsOut)
        // Two days ago, then today.
        #expect(groups.first?.rows.map(\.entry.day) == [Self.day(-2), Self.day(0)])
        #expect(groups.last?.kind == .noDay)
        #expect(groups.last?.rows.map(\.entry.round) == ["プレイガイド二次先行"])
        #expect(groups.count == 3)
        #expect(groups[1].kind == .month(Self.day(5).monthGroupLabel))
    }

    @Test func decidedIsTheWonThenTheRestInEitherOrder() {
        #expect(list.groups(in: .decided, by: .resultsDay).map(\.kind) == [.won, .notWon])
        #expect(list.groups(in: .decided, by: .eventDate).map(\.kind) == [.won, .notWon])
    }

    @Test func byResultsDayTheEarliestComesFirst() {
        let both = LotteryList(events: [Self.later]) { _ in
            Tracking(lotteries: [LotteryEntry(round: "プレイガイド先行", day: Self.day(-1), result: .lost),
                                 LotteryEntry(round: "最速先行抽選", day: Self.day(-10), result: .lost)])
        }
        let lost = both.groups(in: .decided, by: .resultsDay).flatMap(\.rows).map(\.entry.day)
        #expect(lost == [Self.day(-10), Self.day(-1)])
    }

    @Test func byEventDateEachHalfGoesByTheEventsMonth() {
        let groups = list.groups(in: .awaiting, by: .eventDate)
        #expect(groups.flatMap(\.rows).map(\.event.id) == ["soon", "soon", "later", "later"])
        #expect(groups.first?.kind == .month(Self.soon.monthGroupLabel))
        // The rounds of one event in the order the sale runs them.
        let later = groups.flatMap(\.rows).filter { $0.event.id == "later" }.map(\.entry.round)
        #expect(later == ["最速先行抽選", "プレイガイド二次先行"])
    }

    @Test func theCardSamplesTheWaitingSoonestFirst() {
        let next = list.next
        #expect(next.map(\.entry.day) == [Self.day(-2), Self.day(0), Self.day(5), nil])
        #expect(next.first?.isResultsOut() == true)
        #expect(next[2].isResultsOut() == false)
    }

    @Test func aResultCanBeGivenOnlyOnceItsDayHasCome() {
        #expect(LotteryEntry(day: Self.day(1)).canBeDrawn() == false)
        #expect(LotteryEntry(day: Self.day(0)).canBeDrawn())
        #expect(LotteryEntry(day: Self.day(-4)).canBeDrawn())
        #expect(LotteryEntry().canBeDrawn())
    }

    @Test func aWinGivenFromTheListSettlesTheTicketsClass() {
        let entry = LotteryEntry(round: "最速先行抽選", day: Self.day(-1), choices: [Self.sChoice])
        let record = Tracking(lotteries: [entry])
        let won = record.givingResult(.won(Self.sChoice.id), toLottery: entry.id)
        #expect(won.hasTicket)
        #expect(won.seatClass == "S席")
        #expect(record.givingResult(.lost, toLottery: UUID()) == record)
    }

    @Test func takingTheTicketAwayWithASeatWrittenIsAskedAbout() {
        let entry = LotteryEntry(round: "最速先行抽選", day: Self.day(-1), choices: [Self.sChoice],
                                 result: .won(Self.sChoice.id))
        var record = Tracking(lotteries: [entry])
        record.settleSeatClass(since: Tracking())
        let lost = record.givingResult(.lost, toLottery: entry.id)
        #expect(!lost.leavesSeatOrCostBehind(since: record))
        #expect(lost.seatClass.isEmpty)

        record.seat = "1階 L列 23番"
        let lostWithSeat = record.givingResult(.lost, toLottery: entry.id)
        #expect(lostWithSeat.leavesSeatOrCostBehind(since: record))
        #expect(lostWithSeat.clearingSeatAndCost.seat.isEmpty)
    }

    // MARK: - Events that are over

    static let long = Fixtures.event(id: "long", date: Fixtures.day(fromToday: -40))
    static let pastRecords: [Event.ID: Tracking] = records.merging([
        "long": Tracking(lotteries: [
            LotteryEntry(round: "最速先行抽選", day: day(-70), result: .lost),
            LotteryEntry(round: "プレイガイド先行", result: .lost),
            LotteryEntry(round: "プレイガイド二次先行", day: day(-50), result: .lost),
            LotteryEntry(round: "最速先行抽選", day: day(-60), result: .won(nil)),
        ]),
    ]) { first, _ in first }

    let withPast = LotteryList(events: [Self.soon, Self.later, Self.gone, Self.long], includingPast: true) {
        Self.pastRecords[$0.id] ?? Tracking()
    }

    @Test func roundsOfEventsOverAreDecidedOnlyWhenAskedFor() {
        // Awaiting never holds them, and Decided leaves them out until asked.
        #expect(withPast.rows(in: .awaiting).map(\.id) == list.rows(in: .awaiting).map(\.id))
        #expect(withPast.rows(in: .decided).map(\.id) == list.rows(in: .decided).map(\.id))
        let shown = withPast.rows(in: .decided, showingPast: true)
        #expect(shown.count == 7)
        #expect(shown.filter(\.isOver).count == 5)
    }

    @Test func aRoundNobodyAnsweredBeforeItsEventWasOverIsNoResult() throws {
        let row = try #require(withPast.rows(in: .decided, showingPast: true).first { $0.event.id == "gone" })
        #expect(row.entry.isPending)
        #expect(!row.isResultsOut())
        let groups = withPast.groups(in: .decided, by: .resultsDay, showingPast: true)
        #expect(groups.map(\.kind) == [.won, .notWon, .noResult])
        #expect(groups.last?.rows.map(\.event.id) == ["gone"])
    }

    @Test func decidedReadsBackFromNowWhileItShowsThePast() {
        let lost = withPast.groups(in: .decided, by: .resultsDay, showingPast: true)
            .first { $0.kind == .notWon }?.rows.map(\.entry.day)
        // Latest first, and the round with no day still last.
        #expect(lost == [Self.day(-10), Self.day(-50), Self.day(-70), nil])
        let byEvent = withPast.groups(in: .decided, by: .eventDate, showingPast: true)
            .flatMap(\.rows).filter { $0.entry.isWon }.map(\.event.id)
        #expect(byEvent == ["later", "long"])
        // Upcoming alone keeps the earliest first.
        #expect(withPast.groups(in: .decided, by: .resultsDay).map(\.kind) == [.won, .notWon])
    }
}
