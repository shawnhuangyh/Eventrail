import Foundation
import Testing
@testable import Eventrail

struct OnThisDayTests {
    /// Noon on a day of the reader's own calendar.
    static func today(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    static let ticket = Tracking(lotteries: [LotteryEntry(round: "最速先行抽選", result: .won(nil))])

    static func event(_ id: String, _ year: Int, _ month: Int, _ day: Int,
                      at hour: Int? = nil, in zone: TimeZone = Fixtures.tokyo) -> Event {
        Fixtures.event(id: id, date: Fixtures.date(year, month, day, in: zone),
                       startsAt: hour.map { Fixtures.date(year, month, day, $0, in: zone) },
                       timeZone: zone)
    }

    @Test func listsWhatWasGoneToOnThisDayInEarlierYearsMostRecentFirst() {
        let events = [
            Self.event("2023", 2023, 10, 10),
            Self.event("2025-late", 2025, 10, 10, at: 19),
            Self.event("2025-early", 2025, 10, 10, at: 13),
        ]
        let found = OnThisDay(events: events, on: Self.today(2026, 10, 10)) { _ in Self.ticket }
        #expect(found.memories.map(\.id) == ["2025-early", "2025-late", "2023"])
        #expect(found.memories.map(\.yearsAgo) == [1, 1, 3])
        #expect(found.years == 2)
        #expect(found.day == CalendarDay(year: 2026, month: 10, day: 10))
    }

    @Test func leavesOutOtherDaysThisYearAndEventsWithoutATicket() {
        let events = [
            Self.event("other day", 2025, 10, 11),
            Self.event("other month", 2025, 9, 10),
            Self.event("this year", 2026, 10, 10),
            Self.event("no ticket", 2024, 10, 10),
        ]
        let found = OnThisDay(events: events, on: Self.today(2026, 10, 10)) {
            $0.id == "no ticket" ? Tracking() : Self.ticket
        }
        #expect(found.memories.isEmpty)
    }

    @Test func aLotteryLostIsNotAnEventGoneTo() {
        let lost = Tracking(lotteries: [LotteryEntry(round: "最速先行抽選", result: .lost)])
        let found = OnThisDay(events: [Self.event("lost", 2025, 10, 10)],
                              on: Self.today(2026, 10, 10)) { _ in lost }
        #expect(found.memories.isEmpty)
    }

    /// The day the hall says, not the instant the reader's clock puts it at:
    /// a Taipei date is the 10th wherever the reader is.
    @Test func readsTheDayTheHallSaysItFellOn() {
        let taipei = Self.event("taipei", 2025, 10, 10, at: 23, in: Fixtures.taipei)
        let found = OnThisDay(events: [taipei], on: Self.today(2026, 10, 10)) { _ in Self.ticket }
        #expect(found.memories.map(\.id) == ["taipei"])
    }

    @Test func aLeapDayComesRoundOnTheTwentyEighthInAYearWithoutOne() {
        let leap = Self.event("leap", 2024, 2, 29)
        let common = OnThisDay(events: [leap], on: Self.today(2027, 2, 28)) { _ in Self.ticket }
        #expect(common.memories.map(\.id) == ["leap"])
        let leapYear = OnThisDay(events: [leap], on: Self.today(2028, 2, 28)) { _ in Self.ticket }
        #expect(leapYear.memories.isEmpty)
        let itsOwnDay = OnThisDay(events: [leap], on: Self.today(2028, 2, 29)) { _ in Self.ticket }
        #expect(itsOwnDay.memories.map(\.yearsAgo) == [4])
    }
}
