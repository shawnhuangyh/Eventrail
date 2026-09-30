import Foundation
import Testing
@testable import Eventrail

struct EventActivityTests {
    /// Doors 17:30, start 19:00, end 20:30 in Tokyo on 9 May 2027.
    func event(doors: Bool = true, ends: Bool = true) -> Event {
        Fixtures.event(date: Fixtures.date(2027, 5, 9),
                       doorsOpen: doors ? Fixtures.date(2027, 5, 9, 17, 30) : nil,
                       startsAt: Fixtures.date(2027, 5, 9, 19),
                       endsAt: ends ? Fixtures.date(2027, 5, 9, 20, 30) : nil)
    }

    func state(of event: Event, at now: Date) throws -> EventActivityAttributes.ContentState {
        try #require(EventActivities.state(for: event, seat: "", at: now))
    }

    @Test func comesOnTwoHoursBeforeTheDoors() throws {
        let state = try state(of: event(), at: Fixtures.date(2027, 5, 1))
        #expect(EventActivities.opening(of: state) == Fixtures.date(2027, 5, 9, 15, 30))
    }

    @Test func withNoDoorsPublishedComesOnTwoHoursBeforeTheStart() throws {
        let state = try state(of: event(doors: false), at: Fixtures.date(2027, 5, 1))
        #expect(EventActivities.opening(of: state) == Fixtures.date(2027, 5, 9, 17))
        #expect(state.stage == .beforeShow)
    }

    @Test func withNoStartPublishedThereIsNothingToCountTo() {
        let event = Fixtures.event(date: Fixtures.date(2027, 5, 9),
                                   doorsOpen: Fixtures.date(2027, 5, 9, 17, 30))
        #expect(EventActivities.state(for: event, seat: "", at: Fixtures.date(2027, 5, 1)) == nil)
    }

    @Test func withNoEndPublishedTheShowRunsForTheAssumedLength() throws {
        let state = try state(of: event(ends: false), at: Fixtures.date(2027, 5, 9, 20))
        #expect(state.ends == nil)
        #expect(state.runsTo == Fixtures.date(2027, 5, 9, 22))
        #expect(state.stage == .onNow)
    }

    /// 開場 23:30 開演 00:30 終演 02:00 — the start and the end are the next
    /// morning, as ``Event/inOrder(_:_:_:)`` reads them.
    @Test func aNightPastMidnightRunsIntoTheNextMorning() throws {
        let event = Fixtures.event(date: Fixtures.date(2027, 5, 9),
                                   doorsOpen: Fixtures.date(2027, 5, 9, 23, 30),
                                   startsAt: Fixtures.date(2027, 5, 9, 0, 30),
                                   endsAt: Fixtures.date(2027, 5, 9, 2))
        let state = try state(of: event, at: Fixtures.date(2027, 5, 10, 1))
        #expect(state.starts == Fixtures.date(2027, 5, 10, 0, 30))
        #expect(state.runsTo == Fixtures.date(2027, 5, 10, 2))
        #expect(state.stage == .onNow)
    }

    @Test func eachStageOfTheNight() throws {
        let stages = try [
            (Fixtures.date(2027, 5, 9, 16), EventActivityStage.beforeDoors),
            (Fixtures.date(2027, 5, 9, 17, 30), .doorsOpen),
            (Fixtures.date(2027, 5, 9, 18, 54), .doorsOpen),
            (Fixtures.date(2027, 5, 9, 18, 55), .startingSoon),
            (Fixtures.date(2027, 5, 9, 19), .onNow),
            (Fixtures.date(2027, 5, 9, 20, 30), .wrapped),
        ].map { now, expected in (try state(of: event(), at: now).stage, expected) }
        for (stage, expected) in stages { #expect(stage == expected) }
    }

    /// The one change an activity makes by itself goes to the next stage;
    /// "Starting in" is left to the app, so the start is not spent on it.
    @Test func goingStaleMovesOnToTheNextStage() throws {
        let before = try state(of: event(), at: Fixtures.date(2027, 5, 9, 16))
        #expect(before.staleDate == Fixtures.date(2027, 5, 9, 17, 30))
        #expect(before.shownStage(isStale: false) == .beforeDoors)
        #expect(before.shownStage(isStale: true) == .doorsOpen)

        let doors = try state(of: event(), at: Fixtures.date(2027, 5, 9, 18))
        #expect(doors.staleDate == Fixtures.date(2027, 5, 9, 19))
        #expect(doors.nextChange == Fixtures.date(2027, 5, 9, 18, 55))
        #expect(doors.shownStage(isStale: true) == .onNow)

        let show = try state(of: event(), at: Fixtures.date(2027, 5, 9, 19, 30))
        #expect(show.staleDate == Fixtures.date(2027, 5, 9, 20, 30))
        #expect(show.shownStage(isStale: true) == .wrapped)
    }

    /// A door time the page gives as the start itself is dropped: there is no
    /// stretch of doors-open to count down through.
    @Test func aDoorTimeAtTheStartIsDropped() throws {
        let event = Fixtures.event(date: Fixtures.date(2027, 5, 9),
                                   doorsOpen: Fixtures.date(2027, 5, 9, 19),
                                   startsAt: Fixtures.date(2027, 5, 9, 19))
        let state = try state(of: event, at: Fixtures.date(2027, 5, 9, 18))
        #expect(state.doors == nil)
        #expect(state.stage == .beforeShow)
    }
}
