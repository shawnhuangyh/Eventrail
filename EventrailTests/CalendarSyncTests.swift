import Foundation
import Testing
@testable import Eventrail

struct CalendarSyncTests {
    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    /// Tokyo's midnight is 23:00 the evening before in Shanghai; an all-day
    /// entry handed that instant would sit on the wrong day.
    @Test func anUntimedEventKeepsItsHallsDayWestOfTokyo() {
        let event = Fixtures.event(date: Fixtures.date(2027, 5, 9))
        let shanghai = calendar("Asia/Shanghai")
        let day = CalendarSync.floatingDay(of: event, in: shanghai)
        #expect(shanghai.dateComponents([.year, .month, .day, .hour], from: day)
            == DateComponents(year: 2027, month: 5, day: 9, hour: 0))
    }

    @Test func anUntimedEventAbroadKeepsItsOwnHallsDay() {
        let event = Fixtures.event(date: Fixtures.date(2027, 5, 9, in: Fixtures.taipei), timeZone: Fixtures.taipei)
        let angeles = calendar("America/Los_Angeles")
        let day = CalendarSync.floatingDay(of: event, in: angeles)
        #expect(angeles.dateComponents([.year, .month, .day, .hour], from: day)
            == DateComponents(year: 2027, month: 5, day: 9, hour: 0))
    }

    /// A new entry's dates are nil until written; an untimed event was
    /// compared by its day against them and crashed the mirror.
    @Test func aDateNotYetWrittenIsNoDay() {
        let shanghai = calendar("Asia/Shanghai")
        let day = CalendarSync.floatingDay(of: Fixtures.event(date: Fixtures.date(2027, 5, 9)), in: shanghai)
        #expect(!CalendarSync.isDate(nil, inSameDayAs: day, in: shanghai))
        #expect(CalendarSync.isDate(day.addingTimeInterval(23 * 60 * 60), inSameDayAs: day, in: shanghai))
        #expect(!CalendarSync.isDate(day.addingTimeInterval(24 * 60 * 60), inSameDayAs: day, in: shanghai))
    }
}
