import Foundation
import Testing
@testable import Eventrail

/// The reminder that an event's Live Activity can start — see
/// ``ActivityReminders``: when it comes, and which events are owed one.
@MainActor
struct ActivityReminderTests {
    let tokyo = Calendar.gregorian(in: Fixtures.tokyo)

    /// An event `days` from today, from `start` to `end` o'clock in Tokyo.
    func event(_ id: String = "1", inDays days: Int = 3, from start: Double = 18, to end: Double? = 21) -> Event {
        let day = Fixtures.day(fromToday: days)
        return Fixtures.event(id: id, date: day,
                              startsAt: day.addingTimeInterval(start * 3600),
                              endsAt: end.map { day.addingTimeInterval($0 * 3600) })
    }

    func ticketed() -> Tracking {
        var tracking = Tracking()
        tracking.recordTicket()
        return tracking
    }

    @Test func comesEightHoursBeforeTheEventEnds() throws {
        let show = event()
        let reminder = try #require(ActivityReminder(event: show, tracking: ticketed(), calendar: tokyo))
        #expect(reminder.date == show.endsAt!.addingTimeInterval(-EventActivities.longest))
    }

    /// Not in the small hours: at eight instead, or at the start where that
    /// is earlier, and never before the activity can start.
    @Test func waitsForTheMorning() {
        let day = Fixtures.day(fromToday: 3)
        func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3600) }

        #expect(ActivityReminder.fireDate(earliest: at(4), starts: at(10), calendar: tokyo) == at(8))
        #expect(ActivityReminder.fireDate(earliest: at(1), starts: at(6), calendar: tokyo) == at(6))
        #expect(ActivityReminder.fireDate(earliest: at(4.5), starts: at(3), calendar: tokyo) == at(4.5))
        #expect(ActivityReminder.fireDate(earliest: at(13), starts: at(18), calendar: tokyo) == at(13))
    }

    @Test func noneWithoutATicketOrAStart() {
        #expect(ActivityReminder(event: event(), tracking: Tracking(), calendar: tokyo) == nil)
        let unannounced = Fixtures.event(date: Fixtures.day(fromToday: 3))
        #expect(ActivityReminder(event: unannounced, tracking: ticketed(), calendar: tokyo) == nil)
    }

    /// Once the activity can start, there is nothing left to remind of.
    @Test func noneOnceTheMomentHasPassed() {
        let show = event()
        let later = show.endsAt!.addingTimeInterval(-60 * 60)
        #expect(ActivityReminder(event: show, tracking: ticketed(), at: later, calendar: tokyo) == nil)
    }

    @Test func theSoonestAreOwedLeavingOutAnyAlreadyOn() {
        let shows = (1...6).map { event(String($0), inDays: $0 + 1) }
        let due = ActivityReminder.due(in: shows, tracking: { _ in ticketed() }, running: ["2"],
                                       calendar: tokyo)

        #expect(due.map(\.eventID) == ["1", "3", "4", "5"])
        #expect(due.count == ActivityReminder.limit)
    }
}
