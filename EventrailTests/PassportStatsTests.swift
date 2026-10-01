import Foundation
import Testing
@testable import Eventrail

struct PassportStatsTests {
    static let budokan = "東京都千代田区北の丸公園2-3"
    static let osakajo = "大阪府大阪市中央区大阪城3-1"

    /// Four nights across three years, two halls in two prefectures, and one
    /// hall with no address.
    static let nights: [Event] = [
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

    let stats = PassportStats(events: Self.nights) {
        var tracking = Tracking()
        tracking.lotteryEntries = Self.lottery[$0.id]
        return tracking
    }

    @Test func countsTheNights() {
        #expect(stats.totalEvents == 4)
        #expect(stats.events.map(\.id) == ["d", "c", "b", "a"])
        #expect(stats.firstEvent == Fixtures.date(2023, 3, 5))
        #expect(stats.lastEvent == Fixtures.date(2025, 12, 24))
    }

    @Test func measuresOnlyNightsWithBothEnds() {
        #expect(stats.timedEvents == 2)
        #expect(stats.totalDuration == 5 * 3600)
        #expect(stats.shortest.map(\.event.id) == ["b"])
        #expect(stats.longest.map(\.event.id) == ["a"])
    }

    @Test func ranksPerformersOncePerNight() {
        #expect(stats.performers == 2)
        // Billed twice on one night is still one night.
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

    /// A stream, an undisclosed room and a row with no venue are nights the
    /// reader went to, but none of them is a hall.
    @Test func leavesPlaceholderVenuesOutOfTheHalls() {
        let nights = Self.nights + [
            Fixtures.event(id: "e", venue: "!_国内外各所 (ライブビューイング等)"),
            Fixtures.event(id: "f", venue: "!_東京都内某所", venueAddress: "東京都"),
            Fixtures.event(id: "g", venue: "  "),
        ]
        let stats = PassportStats(events: nights) { _ in Tracking() }
        #expect(stats.totalEvents == 7)
        #expect(stats.venues == 3)
        #expect(stats.prefectures == 2)
        #expect(!stats.topVenues.contains { $0.name.hasPrefix("!_") || $0.name.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    @Test func countsLotteriesOverTheNightsTheyWereWrittenOn() {
        #expect(stats.lotteryEvents == 2)
        #expect(stats.lotteryEntries == 7)
        #expect(stats.mostLotteryEntries == 5)
        #expect(stats.averageLotteryEntries == 3.5)
        #expect(stats.topLotteries.map(\.event.id) == ["a", "b"])
    }

    /// Prices on three of four nights — one of them free — across two
    /// classes and one night that names none.
    @Test func addsUpTheTicketsThatHaveAPrice() {
        let costs: [Event.ID: (Int?, String)] = [
            "a": (9_900, "S席"), "b": (0, " S席 "), "c": (7_000, ""), "d": (nil, "A席"),
        ]
        let stats = PassportStats(events: Self.nights) {
            var tracking = Tracking()
            tracking.cost = costs[$0.id]?.0
            tracking.seatClass = costs[$0.id]?.1 ?? ""
            return tracking
        }
        // A free seat is a price; a class with no price is not a ticket here.
        #expect(stats.tickets.map(\.id) == ["a", "c", "b"])
        #expect(stats.ticketSpending == 16_900)
        #expect(stats.highestTicketPrice == 9_900)
        #expect(stats.lowestTicketPrice == 0)
        #expect(stats.averageTicketPrice == 16_900.0 / 3)
        // Trimmed into one class, and the night that names none goes last.
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
        let stats = PassportStats(events: Self.nights) {
            var tracking = Tracking()
            tracking.cost = classes[$0.id]?.0
            tracking.seatClass = classes[$0.id]?.1 ?? ""
            return tracking
        }
        #expect(stats.ticketTypes.map(\.seatClass) == ["S席", "A席", ""])
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
        #expect(PassportStats.years(of: Self.nights) == [2025, 2023])
        #expect(PassportStats.events(Self.nights, in: .year(2025)).map(\.id) == ["b", "c", "d"])
        #expect(PassportStats.events(Self.nights, in: .allTime).count == 4)
    }

    /// A zone as far east as the calendar goes, so its New Year's midnight is
    /// still the 31st of December wherever the tests happen to run.
    @Test func readsTheYearWhereTheNightWasHeld() {
        let kiritimati = TimeZone(identifier: "Pacific/Kiritimati")!
        let newYear = Fixtures.event(date: Fixtures.date(2026, 1, 1, in: kiritimati),
                                     timeZone: kiritimati)
        #expect(PassportStats.year(of: newYear) == 2026)
        #expect(PassportStats.years(of: [newYear]) == [2026])
        #expect(PassportStats(events: [newYear]) { _ in Tracking() }
            .tally(by: .year).map(\.value) == [2026])
    }

    /// A finish typed earlier than the start is read as the next morning, and
    /// a night that long is a typo, not the longest night on record.
    @Test func leavesOutANightThatWrappedRoundTheClock() {
        let nights = [
            Fixtures.event(id: "typo", date: Fixtures.date(2024, 5, 1),
                           startsAt: Fixtures.date(2024, 5, 1, 18, 0),
                           endsAt: Fixtures.date(2024, 5, 2, 17, 30)),
            Fixtures.event(id: "allnight", date: Fixtures.date(2024, 6, 1),
                           startsAt: Fixtures.date(2024, 6, 1, 22, 0),
                           endsAt: Fixtures.date(2024, 6, 2, 5, 0)),
        ]
        let stats = PassportStats(events: nights) { _ in Tracking() }
        #expect(stats.timedEvents == 1)
        #expect(stats.totalDuration == 7 * 3600)
        #expect(stats.longest.map(\.event.id) == ["allnight"])
    }

    /// Nights of equal length keep one order: by the night, then the id.
    @Test func ordersNightsOfEqualLengthByDate() {
        let nights = ["x", "w", "v", "u"].enumerated().map { index, id in
            Fixtures.event(id: id, date: Fixtures.date(2024, 1, 1 + index),
                           startsAt: Fixtures.date(2024, 1, 1 + index, 18, 0),
                           endsAt: Fixtures.date(2024, 1, 1 + index, 20, 0))
        }
        let stats = PassportStats(events: nights) { _ in Tracking() }
        #expect(stats.shortest.map(\.event.id) == ["x", "w"])
        #expect(stats.longest.map(\.event.id) == ["u", "v"])
    }
}
