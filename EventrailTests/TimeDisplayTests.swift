import Foundation
import Testing
@testable import Eventrail

struct TimeDisplayTests {
    @Test func venueTimeLeavesTheEventAsItIs() {
        let event = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 18))
        #expect(event.shown(on: .venue) == event)
    }

    @Test func myTimeMovesTheClockNotTheInstant() {
        let event = Fixtures.event(startsAt: Fixtures.date(2027, 5, 9, 18))
        let shown = event.shown(on: .local)
        #expect(shown.timeZone == .current)
        #expect(shown.startsAt == event.startsAt)
        // The day is the day of the first published time, on the reader's clock.
        #expect(shown.date == event.startsAt)
    }

    @Test func anEventWithNoTimeKeepsItsHallsDay() {
        let event = Fixtures.event()
        #expect(event.shown(on: .local) == event)
    }
}
