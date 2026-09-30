import Foundation
import Testing
@testable import Eventrail

struct EventProgressTests {
    /// Doors 17:30, start 19:00, end 20:30 in Tokyo on 9 May 2027.
    func event(doors: Bool = true, ends: Bool = true) -> Event {
        Fixtures.event(date: Fixtures.date(2027, 5, 9),
                       doorsOpen: doors ? Fixtures.date(2027, 5, 9, 17, 30) : nil,
                       startsAt: Fixtures.date(2027, 5, 9, 19),
                       endsAt: ends ? Fixtures.date(2027, 5, 9, 20, 30) : nil)
    }

    @Test func aDayStillToComeIsAheadWithNothingFilled() {
        let progress = EventProgress(event: event(), at: Fixtures.date(2027, 5, 7, 12))
        #expect(progress.phase == .ahead(days: 2))
        #expect(progress.fraction == 0)
        #expect(!progress.isToday)
    }

    @Test func beforeTheDoorsOnTheDayCountsToTheDoors() {
        let progress = EventProgress(event: event(), at: Fixtures.date(2027, 5, 9, 15))
        #expect(progress.phase == .beforeDoors(opening: Fixtures.date(2027, 5, 9, 17, 30)))
        #expect(progress.fraction == 0)
        #expect(progress.isToday)
    }

    @Test func withNoDoorsPublishedTheDayCountsToTheStart() {
        let progress = EventProgress(event: event(doors: false), at: Fixtures.date(2027, 5, 9, 18))
        #expect(progress.phase == .beforeShow(starting: Fixtures.date(2027, 5, 9, 19)))
        #expect(progress.fraction == 0)
    }

    /// Halfway from the doors to the start is a quarter of the line: the
    /// doors stand at its start and the start at its middle.
    @Test func betweenTheDoorsAndTheStartFillsTheFirstHalf() {
        let progress = EventProgress(event: event(), at: Fixtures.date(2027, 5, 9, 18, 15))
        #expect(progress.phase == .doorsOpen(showStarts: Fixtures.date(2027, 5, 9, 19)))
        #expect(progress.fraction == 0.25)
        #expect(progress.isUnderway)
    }

    @Test func duringTheShowFillsTheSecondHalf() {
        let progress = EventProgress(event: event(), at: Fixtures.date(2027, 5, 9, 19, 45))
        #expect(progress.phase == .onNow(ends: Fixtures.date(2027, 5, 9, 20, 30)))
        #expect(progress.fraction == 0.75)
    }

    @Test func withNoEndPublishedTheShowRunsForTheAssumedLength() {
        let progress = EventProgress(event: event(ends: false), at: Fixtures.date(2027, 5, 9, 20, 30))
        #expect(progress.phase == .onNow(ends: nil))
        #expect(progress.fraction == 0.75)
    }

    @Test func afterTheEndOnTheDayIsAWrap() {
        let progress = EventProgress(event: event(), at: Fixtures.date(2027, 5, 9, 21))
        #expect(progress.phase == .wrapped)
        #expect(progress.fraction == 1)
    }

    @Test func onceTheDayIsOverItIsOver() {
        let progress = EventProgress(event: event(), at: Fixtures.date(2027, 5, 10, 12))
        #expect(progress.phase == .over)
        #expect(progress.fraction == 1)
        #expect(!progress.isToday)
    }

    /// The page prints 01:00 for an end after midnight; read in order, that is
    /// the next morning, and the show is still on after its day is over.
    @Test func aShowRunningPastMidnightIsStillOn() {
        let late = Fixtures.event(date: Fixtures.date(2027, 5, 9),
                                  startsAt: Fixtures.date(2027, 5, 9, 23),
                                  endsAt: Fixtures.date(2027, 5, 9, 1))
        let progress = EventProgress(event: late, at: Fixtures.date(2027, 5, 10, 0, 30))
        #expect(progress.phase == .onNow(ends: Fixtures.date(2027, 5, 10, 1)))
        #expect(progress.fraction == 0.875)
    }
}
