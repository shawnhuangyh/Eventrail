import Foundation
import Testing
@testable import Eventrail

struct PassportStatsTests {
    static let budokan = "東京都千代田区北の丸公園2-3"
    static let osakajo = "大阪府大阪市中央区大阪城3-1"

    /// Four events across three years, two halls in two prefectures, and one
    /// hall with no address.
    static let events: [Event] = [
        Fixtures.event(id: "a", venue: "日本武道館", venueAddress: budokan,
                       date: Fixtures.date(2023, 3, 5),
                       startsAt: Fixtures.date(2023, 3, 5, 18, 0),
                       endsAt: Fixtures.date(2023, 3, 5, 21, 0),
                       performers: ["水瀬いのり", "水瀬いのり"]),
        Fixtures.event(id: "b", venue: "日本武道館", venueAddress: budokan,
                       date: Fixtures.date(2025, 6, 1),
                       startsAt: Fixtures.date(2025, 6, 1, 17, 0),
                       endsAt: Fixtures.date(2025, 6, 1, 19, 0),
                       performers: ["水瀬いのり", "小倉唯"]),
        Fixtures.event(id: "c", venue: "大阪城ホール", venueDetail: osakajo + " · 16,000人",
                       date: Fixtures.date(2025, 9, 20),
                       startsAt: Fixtures.date(2025, 9, 20, 18, 0),
                       performers: ["小倉唯"]),
        Fixtures.event(id: "d", venue: "Somewhere", date: Fixtures.date(2025, 12, 24)),
    ]

    static let lottery: [Event.ID: Int] = ["a": 5, "b": 2]

    let stats = PassportStats(events: Self.events) {
        var tracking = Tracking()
        // Split over two rounds where there are enough, so the figures are
        // the applications added up rather than the rounds counted; and a
        // first-come round beside them, which adds nothing.
        if let count = Self.lottery[$0.id] {
            tracking.lotteries = count > 1
                ? [LotteryEntry(round: "最速先行抽選", applications: count - 1), LotteryEntry(round: "プレイガイド先行")]
                : [LotteryEntry(applications: count)]
            tracking.lotteries.append(LotteryEntry(round: "一般発売", applications: 4))
        }
        return tracking
    }

    @Test func countsTheEvents() {
        #expect(stats.totalEvents == 4)
        #expect(stats.events.map(\.id) == ["d", "c", "b", "a"])
        #expect(stats.firstEvent == Fixtures.date(2023, 3, 5))
        #expect(stats.lastEvent == Fixtures.date(2025, 12, 24))
    }

    @Test func measuresOnlyEventsWithBothEnds() {
        #expect(stats.timedEvents == 2)
        #expect(stats.totalDuration == 5 * 3600)
        #expect(stats.shortest.map(\.event.id) == ["b"])
        #expect(stats.longest.map(\.event.id) == ["a"])
    }

    @Test func ranksPerformersOncePerEvent() {
        #expect(stats.performers == 2)
        // Billed twice on one event is still one event.
        #expect(stats.topPerformers.map(\.name) == ["小倉唯", "水瀬いのり"])
        #expect(stats.topPerformers.map(\.count) == [2, 2])
    }

    @Test func ranksVenuesWithTheirPrefecture() {
        #expect(stats.venues == 3)
        let top = stats.topVenues.first
        #expect(top?.name == "日本武道館")
        #expect(top?.count == 2)
        #expect(top?.detail == "東京都")
        #expect(stats.topVenues.first { $0.name == "大阪城ホール" }?.detail == "大阪府")
        #expect(stats.topVenues.first { $0.name == "Somewhere" }?.detail == nil)
        #expect(stats.prefectures == 2)
    }

    /// A stream, an undisclosed room and a row with no venue are events the
    /// reader went to, but none of them is a hall.
    @Test func leavesPlaceholderVenuesOutOfTheHalls() {
        let events = Self.events + [
            Fixtures.event(id: "e", venue: "!_国内外各所 (ライブビューイング等)"),
            Fixtures.event(id: "f", venue: "!_東京都内某所", venueAddress: "東京都"),
            Fixtures.event(id: "g", venue: "  "),
        ]
        let stats = PassportStats(events: events) { _ in Tracking() }
        #expect(stats.totalEvents == 7)
        #expect(stats.venues == 3)
        #expect(stats.prefectures == 2)
        #expect(!stats.topVenues.contains { $0.name.hasPrefix("!_") || $0.name.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    @Test func countsLotteriesOverTheEventsTheyWereWrittenOn() {
        #expect(stats.lotteryEvents == 2)
        #expect(stats.lotteryEntries == 7)
        #expect(stats.mostLotteryEntries == 5)
        #expect(stats.averageLotteryEntries == 3.5)
        #expect(stats.topLotteries.map(\.event.id) == ["a", "b"])
    }

    /// Prices on three of four events — one of them free — across two
    /// classes and one event that names none.
    @Test func addsUpTheTicketsThatHaveAPrice() {
        let costs: [Event.ID: (Int?, String)] = [
            "a": (9_900, "S席"), "b": (0, " S席 "), "c": (7_000, ""), "d": (nil, "A席"),
        ]
        let stats = PassportStats(events: Self.events) {
            var tracking = Tracking()
            tracking.cost = costs[$0.id]?.0.map { Decimal($0) }
            tracking.seatClass = costs[$0.id]?.1 ?? ""
            return tracking
        }
        // A free seat is a price; a class with no price is not a ticket here.
        #expect(stats.tickets.map(\.id) == ["a", "c", "b"])
        #expect(stats.ticketSpending == 16_900)
        #expect(stats.highestTicketPrice == 9_900)
        #expect(stats.lowestTicketPrice == 0)
        #expect(stats.averageTicketPrice == 16_900.0 / 3)
        // Trimmed into one class, and the event that names none goes last.
        #expect(stats.ticketTypes.map(\.seatClass) == ["S席", ""])
        #expect(stats.ticketTypes.first?.count == 2)
        #expect(stats.ticketTypes.first?.spent == 9_900)
        #expect(stats.ticketTypes.first?.lowest == 0)
        #expect(stats.ticketTypes.first?.highest == 9_900)
    }

    @Test func ordersTicketTypesByHowManyThenByPrice() {
        let classes: [Event.ID: (Int, String)] = [
            "a": (5_000, "A席"), "b": (12_000, "S席"), "c": (3_000, ""), "d": (4_000, ""),
        ]
        let stats = PassportStats(events: Self.events) {
            var tracking = Tracking()
            tracking.cost = classes[$0.id].map { Decimal($0.0) }
            tracking.seatClass = classes[$0.id]?.1 ?? ""
            return tracking
        }
        #expect(stats.ticketTypes.map(\.seatClass) == ["S席", "A席", ""])
    }

    // MARK: - Tickets in other currencies

    /// A euro buys 180 yen, 36 Taiwan dollars and 7.5 yuan.
    static let rates = CurrencyRates(base: "EUR", rates: ["JPY": 180, "TWD": 36, "CNY": 7.5],
                                     published: .now, readAt: .now)

    func stats(paying paid: [Event.ID: Money], in currency: String,
               at rates: CurrencyRates?) -> PassportStats {
        PassportStats(events: Self.events, currency: currency, rates: rates) { event in
            var tracking = Tracking()
            tracking.cost = paid[event.id]?.amount
            tracking.currency = paid[event.id]?.currency ?? ""
            return tracking
        }
    }

    /// Yen and Taiwan dollars added up in yen, through the euro: NT$1,000 is
    /// 1000 / 36 euros, which is 5,000 yen.
    @Test func addsUpTicketsPaidInSeveralCurrencies() {
        let stats = stats(paying: ["a": Money(amount: 9000, currency: "JPY"),
                                   "b": Money(amount: 1000, currency: "TWD")],
                          in: "JPY", at: Self.rates)
        #expect(stats.tickets.map(\.id) == ["a", "b"])
        #expect(abs(stats.ticketSpending - 14_000) < 0.001)
        #expect(stats.isConverted)
        #expect(stats.unconvertedTickets == 0)
        // Paid in two currencies, so there is no one figure as it was paid.
        #expect(stats.paidCurrency == nil)
        #expect(!stats.showsPaid)
        #expect(stats.paidSpending == nil)
    }

    /// Every ticket paid in yen and read in yuan: each figure can also say
    /// what it was in yen, exactly.
    @Test func readsYenInAnotherCurrency() {
        let stats = stats(paying: ["a": Money(amount: 9000, currency: "JPY"),
                                   "b": Money(amount: 18000, currency: "JPY")],
                          in: "CNY", at: Self.rates)
        #expect(abs(stats.ticketSpending - 1125) < 0.001)
        #expect(stats.paidCurrency == "JPY")
        #expect(stats.showsPaid)
        #expect(stats.paidSpending == Money(amount: 27000, currency: "JPY"))
        #expect(stats.averagePaid == 13500)
        #expect(stats.tickets.first?.paid == Money(amount: 18000, currency: "JPY"))
        #expect(stats.ticketTypes.first?.paidAverage == Money(amount: 13500, currency: "JPY"))
    }

    /// With no rates on the device, a ticket paid in another currency is left
    /// out and counted — never read as though it were yen.
    @Test func leavesOutWhatTheRatesCannotConvert() {
        let stats = stats(paying: ["a": Money(amount: 9000, currency: "JPY"),
                                   "b": Money(amount: 1000, currency: "TWD")],
                          in: "JPY", at: nil)
        #expect(stats.tickets.map(\.id) == ["a"])
        #expect(stats.ticketSpending == 9000)
        #expect(stats.unconvertedTickets == 1)
        #expect(!stats.isConverted)
    }

    @Test func readsRatesThroughTheirBase() {
        #expect(Self.rates.rate(from: "JPY", to: "JPY") == 1)
        #expect(Self.rates.rate(from: "EUR", to: "TWD") == 36)
        #expect(Self.rates.rate(from: "TWD", to: "EUR") == 1.0 / 36)
        #expect(Self.rates.rate(from: "TWD", to: "JPY") == 5)
        #expect(Self.rates.rate(from: "JPY", to: "XYZ") == nil)
    }

    @Test func tallyByYearFillsTheGaps() {
        let years = stats.tally(by: .year)
        #expect(years.map(\.value) == [2023, 2024, 2025])
        #expect(years.map(\.count) == [1, 0, 3])
    }

    @Test func tallyByMonthHasTwelveColumns() {
        let months = stats.tally(by: .month)
        #expect(months.count == 12)
        #expect(months.map(\.count).reduce(0, +) == 4)
        #expect(months[2].count == 1)
    }

    @Test func tallyByWeekdayHasSevenColumns() {
        let days = stats.tally(by: .weekday)
        #expect(days.count == 7)
        #expect(days.map(\.count).reduce(0, +) == 4)
    }

    @Test func anEmptyLibraryAddsUpToNothing() {
        let empty = PassportStats(events: []) { _ in Tracking() }
        #expect(empty.totalEvents == 0)
        #expect(empty.averageLotteryEntries == 0)
        #expect(empty.tickets.isEmpty)
        #expect(empty.averageTicketPrice == 0)
        #expect(empty.highestTicketPrice == nil)
        #expect(empty.tally(by: .year).isEmpty)
        #expect(empty.firstEvent == nil)
    }

    @Test func scopesByYear() {
        #expect(PassportStats.years(of: Self.events) == [2025, 2023])
        #expect(PassportStats.events(Self.events, in: .year(2025)).map(\.id) == ["b", "c", "d"])
        #expect(PassportStats.events(Self.events, in: .allTime).count == 4)
    }

    /// A zone as far east as the calendar goes, so its New Year's midnight is
    /// still the 31st of December wherever the tests happen to run.
    @Test func readsTheYearWhereTheEventWasHeld() {
        let kiritimati = TimeZone(identifier: "Pacific/Kiritimati")!
        let newYear = Fixtures.event(date: Fixtures.date(2026, 1, 1, in: kiritimati),
                                     timeZone: kiritimati)
        #expect(PassportStats.year(of: newYear) == 2026)
        #expect(PassportStats.years(of: [newYear]) == [2026])
        #expect(PassportStats(events: [newYear]) { _ in Tracking() }
            .tally(by: .year).map(\.value) == [2026])
    }

    /// A finish typed earlier than the start is read as the next morning, and
    /// an event that long is a typo, not the longest event on record.
    @Test func leavesOutAnEventThatWrappedRoundTheClock() {
        let events = [
            Fixtures.event(id: "typo", date: Fixtures.date(2024, 5, 1),
                           startsAt: Fixtures.date(2024, 5, 1, 18, 0),
                           endsAt: Fixtures.date(2024, 5, 2, 17, 30)),
            Fixtures.event(id: "allnight", date: Fixtures.date(2024, 6, 1),
                           startsAt: Fixtures.date(2024, 6, 1, 22, 0),
                           endsAt: Fixtures.date(2024, 6, 2, 5, 0)),
        ]
        let stats = PassportStats(events: events) { _ in Tracking() }
        #expect(stats.timedEvents == 1)
        #expect(stats.totalDuration == 7 * 3600)
        #expect(stats.longest.map(\.event.id) == ["allnight"])
    }

    /// Events of equal length keep one order: by the date, then the id.
    @Test func ordersEventsOfEqualLengthByDate() {
        let events = ["x", "w", "v", "u"].enumerated().map { index, id in
            Fixtures.event(id: id, date: Fixtures.date(2024, 1, 1 + index),
                           startsAt: Fixtures.date(2024, 1, 1 + index, 18, 0),
                           endsAt: Fixtures.date(2024, 1, 1 + index, 20, 0))
        }
        let stats = PassportStats(events: events) { _ in Tracking() }
        #expect(stats.shortest.map(\.event.id) == ["x", "w"])
        #expect(stats.longest.map(\.event.id) == ["u", "v"])
    }
}
