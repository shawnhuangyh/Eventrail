import Foundation
import Testing
@testable import Eventrail

/// A reader can set their phone to the Japanese calendar, where 2026 is the
/// year 8 of Reiwa, or to the Buddhist one, where it is 2569. Every day the
/// app counts or keeps is a Gregorian one whatever the phone is set to: read
/// off the reader's calendar and handed to another, a day landed in 4044 or
/// in the year 8.
struct GregorianTests {
    /// A phone set to `identifier`, in Tokyo.
    static func reader(_ identifier: Calendar.Identifier, in zone: TimeZone = Fixtures.tokyo) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = zone
        return calendar
    }

    nonisolated static let calendars: [Calendar.Identifier] = [.gregorian, .japanese, .buddhist]

    @Test(arguments: calendars)
    func aDayIsCountedOnTheGregorianCalendar(_ identifier: Calendar.Identifier) {
        let reader = Self.reader(identifier)
        let day = CalendarDay(Fixtures.date(2026, 10, 12, 15), in: reader)
        #expect(day == CalendarDay(year: 2026, month: 10, day: 12))
        #expect(day.date(in: reader) == Fixtures.date(2026, 10, 12))
        #expect(day.daysAway(from: Fixtures.date(2026, 10, 9, 20), in: reader) == 3)
    }

    /// What the builds before kept on a phone set to either calendar reads
    /// back as the day it was.
    @Test func aDayKeptInTheYearOfAnEraReadsAsTheYearItWas() throws {
        let day = CalendarDay(year: 2026, month: 10, day: 12)
        #expect(CalendarDay(text: "0008-10-12") == day)
        #expect(CalendarDay(text: "2569-10-12") == day)
        #expect(CalendarDay(text: "2026-10-12") == day)
        #expect(try JSONDecoder().decode(CalendarDay.self, from: Data(#""0008-10-12""#.utf8)) == day)
        // Read so, and not taken as this build's own, so a column holding it
        // is not written back by a note edited beside it.
        let kept = #"[{"applications":1,"day":"0008-10-12","id":"00000000-0000-4000-8000-000000000002","result":"pending"}]"#
        #expect(LotteryEntry.entries(inColumn: kept)?.first?.day == day)
        #expect(!LotteryEntry.understands(column: kept))
    }

    /// An untimed event written to the calendar as an all-day entry: on a
    /// phone set to the Japanese calendar it landed in 4044, outside the
    /// sweep, and every mirror wrote it again.
    @Test(arguments: calendars)
    func anUntimedEventKeepsItsYearInTheCalendar(_ identifier: Calendar.Identifier) {
        let shanghai = Self.reader(identifier, in: TimeZone(identifier: "Asia/Shanghai")!)
        let day = CalendarSync.floatingDay(of: Fixtures.event(date: Fixtures.date(2027, 5, 9)), in: shanghai)
        #expect(Calendar.gregorian(in: shanghai.timeZone).dateComponents([.year, .month, .day, .hour], from: day)
            == DateComponents(year: 2027, month: 5, day: 9, hour: 0))
        #expect(CalendarSync.isDate(day.addingTimeInterval(23 * 60 * 60), inSameDayAs: day, in: shanghai))
    }

    /// The reminder's trigger is matched against the phone's own calendar, so
    /// it is written in that calendar's terms, era and all: the Gregorian
    /// year handed over as it stood was Reiwa 2026, an evening never reached.
    @Test(arguments: calendars)
    func aReminderComesOnItsGregorianEvening(_ identifier: Calendar.Identifier) throws {
        let reader = Self.reader(identifier)
        let day = CalendarDay(year: 2026, month: 10, day: 12)
        let evening = try #require(LotteryReminder.evening(of: day, in: reader))
        #expect(evening == Fixtures.date(2026, 10, 12, 20))
        let components = LotteryReminder.components(of: day, in: reader)
        #expect(components.timeZone == nil)
        #expect(reader.date(from: components) == evening)

        let event = Fixtures.event(date: Fixtures.day(fromToday: 30))
        let soon = LotteryEntry(round: "最速先行抽選", day: LotteryListTests.day(3))
        let list = LotteryList(events: [event]) { _ in Tracking(lotteries: [soon]) }
        #expect(LotteryReminder.due(in: list, calendar: reader).map(\.entryID) == [soon.id])
    }

    /// The year an event fell in, which the Passport counts its years by.
    @Test func anEventIsDatedOnTheGregorianCalendar() {
        let heisei = Fixtures.event(date: Fixtures.date(2018, 6, 1))
        #expect(PassportStats.year(of: heisei) == 2018)
        #expect(Calendar.gregorian().component(.year, from: heisei.localDay) == 2018)
        #expect(heisei.daysAway == nil)
    }
}
