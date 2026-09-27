import Foundation
import Testing
@testable import Eventrail

struct EventTests {
    // MARK: - Reading the published clock in the hall's zone

    @Test func publishedInAnotherZoneKeepsTheWallClock() throws {
        let tokyo = Fixtures.event(date: Fixtures.date(2027, 5, 9),
                                   doorsOpen: Fixtures.date(2027, 5, 9, 17, 0),
                                   startsAt: Fixtures.date(2027, 5, 9, 18, 0))
        let taipei = tokyo.published(in: Fixtures.taipei)

        #expect(taipei.timeZone == Fixtures.taipei)
        // 18:00 at the hall is 18:00 in Taipei, an hour after 18:00 in Tokyo.
        #expect(taipei.startsAt == Fixtures.date(2027, 5, 9, 18, 0, in: Fixtures.taipei))
        #expect(taipei.doorsOpen == Fixtures.date(2027, 5, 9, 17, 0, in: Fixtures.taipei))
        #expect(taipei.date == Fixtures.date(2027, 5, 9, in: Fixtures.taipei))
        let start = try #require(taipei.startsAt)
        #expect(start.timeIntervalSince(try #require(tokyo.startsAt)) == 3600)
        #expect(taipei.endsAt == nil)
    }

    @Test func publishedInTheSameZoneIsUnchanged() {
        let event = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 18, 0))
        #expect(event.published(in: Fixtures.tokyo) == event)
    }

    @Test func offsetLineNamesTheOffsetNotAPlace() {
        let event = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 18, 0))
        let line = event.offsetLine(in: Fixtures.tokyo)
        #expect(line.contains("9"))
        #expect(!line.contains("Japan"))
    }

    // MARK: - Merging a fresh import

    @Test func aListRowDoesNotBlankWhatTheEventPageSupplied() {
        let detailed = Fixtures.event(
            venueDetail: "東京都千代田区 · 14,471人", venueAddress: "東京都千代田区",
            startsAt: Fixtures.date(2027, 5, 9, 18, 0), performers: ["A"],
            summary: "概要", isDetailed: true, detailFormat: 1)
        let row = Fixtures.event(title: "Renamed")

        let merged = detailed.merging(row)
        #expect(merged.title == "Renamed")
        #expect(merged.venueAddress == "東京都千代田区")
        #expect(merged.venueDetail == "東京都千代田区 · 14,471人")
        #expect(merged.startsAt == Fixtures.date(2027, 5, 9, 18, 0))
        #expect(merged.performers.map(\.name) == ["A"])
        #expect(merged.summary == "概要")
        #expect(merged.isDetailed)
        #expect(merged.detailFormat == 1)
    }

    /// The page no longer prints a start time or a 概要: a fresh read of it
    /// says so, where a listing row would have said nothing.
    @Test func aReadOfThePageClearsWhatThePageNoLongerPrints() {
        let held = Fixtures.event(
            venueAddress: "東京都千代田区", startsAt: Fixtures.date(2027, 5, 9, 18, 0),
            endsAt: Fixtures.date(2027, 5, 9, 21, 0), performers: ["A"],
            summary: "S席 9,000円", isDetailed: true, detailFormat: 1)
        let page = Fixtures.event(isDetailed: true, detailFormat: 1)

        let merged = held.merging(page)
        #expect(merged.startsAt == nil)
        #expect(merged.endsAt == nil)
        #expect(merged.summary == nil)
        #expect(merged.performers.isEmpty)
        // From the hall's own page, whose failure an import shrugs off.
        #expect(merged.venueAddress == "東京都千代田区")
    }

    @Test func aReimportDoesNotPutAHallAbroadBackOnTokyoTime() {
        let placed = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 18, 0))
            .published(in: Fixtures.taipei)
        let reimported = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 18, 30))

        let merged = placed.merging(reimported)
        #expect(merged.timeZone == Fixtures.taipei)
        #expect(merged.startsAt == Fixtures.date(2027, 5, 9, 18, 30, in: Fixtures.taipei))
    }

    // MARK: - How much of the page was read

    @Test(arguments: [
        (false, nil as Int?, false),
        (true, nil, false),
        (true, 0, false),
        (true, Event.currentDetailFormat, true),
    ])
    func fullyDetailedNeedsTheCurrentFormat(detailed: Bool, format: Int?, expected: Bool) {
        let event = Fixtures.event(isDetailed: detailed, detailFormat: format)
        #expect(event.isFullyDetailed == expected)
    }

    // MARK: - A read that found nothing new

    /// Opening an event reads its page again; finding it as it was is not a
    /// change, whatever hour the read and the old edit date carry.
    @Test func aReadThatFoundNothingNewIsTheSameRead() {
        var held = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 18), isDetailed: true, detailFormat: 3)
        held.editedAt = Fixtures.date(2027, 2, 1, 14, 37)
        held.readAt = Fixtures.date(2027, 5, 1, 14, 37)
        var read = held
        read.editedAt = Fixtures.date(2027, 2, 1)
        read.readAt = Fixtures.date(2027, 5, 2, 9, 5)
        #expect(read.isSameRead(as: held))

        var moved = read
        moved.startsAt = Fixtures.date(2027, 5, 9, 18, 30)
        #expect(!moved.isSameRead(as: held))
        var edited = read
        edited.editedAt = Fixtures.date(2027, 4, 30)
        #expect(!edited.isSameRead(as: held))
    }

    // MARK: - Where the night stands

    @Test func sortDatePrefersTheStartTime() {
        let start = Fixtures.date(2027, 5, 9, 18, 0)
        #expect(Fixtures.event(startsAt: start).sortDate == start)
        #expect(Fixtures.event().sortDate == Fixtures.date(2027, 5, 9))
    }

    @Test func daysAwayCountsWrittenDates() {
        #expect(Fixtures.event(date: Fixtures.day(fromToday: 0)).daysAway == 0)
        #expect(Fixtures.event(date: Fixtures.day(fromToday: 1)).daysAway == 1)
        #expect(Fixtures.event(date: Fixtures.day(fromToday: 30)).daysAway == 30)
        #expect(Fixtures.event(date: Fixtures.day(fromToday: -1)).daysAway == nil)
    }

    @Test func isUpcomingUntilItsDayIsOver() {
        #expect(Fixtures.event(date: Fixtures.day(fromToday: 1)).isUpcoming)
        #expect(!Fixtures.event(date: Fixtures.day(fromToday: -2)).isUpcoming)
    }

    @Test func isUpcomingAnywhereUntilTheLastZoneLeavesItsDay() {
        // 9 May on Tokyo time: over there at 15:00 GMT on the 9th, and not
        // over everywhere until 12:00 GMT on the 10th — the morning of the
        // 9th in Los Angeles is when Tokyo's day ends.
        let event = Fixtures.event(date: Fixtures.date(2027, 5, 9))
        let gmt = TimeZone.gmt
        #expect(event.isUpcomingAnywhere(asOf: Fixtures.date(2027, 5, 9, 16, in: gmt)))
        #expect(event.isUpcomingAnywhere(asOf: Fixtures.date(2027, 5, 10, 11, 59, in: gmt)))
        #expect(!event.isUpcomingAnywhere(asOf: Fixtures.date(2027, 5, 10, 12, in: gmt)))
    }

    @Test func fallsComparesDaysNotInstants() {
        let event = Fixtures.event(date: Fixtures.day(fromToday: 3))
        let today = Calendar.current.startOfDay(for: .now)
        let later = Calendar.current.date(byAdding: .day, value: 3, to: today)!
        #expect(event.falls(in: today ... later))
        #expect(!event.falls(in: today ... Calendar.current.date(byAdding: .day, value: 2, to: today)!))
    }
}
