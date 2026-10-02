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

    /// Eight hours, the system's limit, before the end: started any earlier
    /// it would be ended before the show was.
    @Test func canStartEightHoursBeforeTheEnd() throws {
        let state = try state(of: event(), at: Fixtures.date(2027, 5, 1))
        #expect(EventActivities.earliestStart(of: state) == Fixtures.date(2027, 5, 9, 12, 30))
    }

    @Test func withNoEndPublishedCanStartEightHoursBeforeTheAssumedOne() throws {
        let state = try state(of: event(ends: false), at: Fixtures.date(2027, 5, 1))
        #expect(EventActivities.earliestStart(of: state) == Fixtures.date(2027, 5, 9, 14))
    }

    @Test func withNoDoorsPublishedTheStartComesFirst() throws {
        let state = try state(of: event(doors: false), at: Fixtures.date(2027, 5, 1))
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

    /// Every stage still to come, each with its stretch — what the activity
    /// moves on through with nobody sending it anything.
    @Test func laysOutTheRestOfTheNight() throws {
        let state = try state(of: event(), at: Fixtures.date(2027, 5, 9, 16))
        #expect(state.phases() == [
            EventActivityPhase(stage: .beforeDoors, until: Fixtures.date(2027, 5, 9, 17, 30)),
            EventActivityPhase(stage: .doorsOpen, from: Fixtures.date(2027, 5, 9, 17, 30),
                               until: Fixtures.date(2027, 5, 9, 18, 55)),
            EventActivityPhase(stage: .startingSoon, from: Fixtures.date(2027, 5, 9, 18, 55),
                               until: Fixtures.date(2027, 5, 9, 19)),
            EventActivityPhase(stage: .onNow, from: Fixtures.date(2027, 5, 9, 19),
                               until: Fixtures.date(2027, 5, 9, 20, 30)),
            EventActivityPhase(stage: .wrapped, from: Fixtures.date(2027, 5, 9, 20, 30)),
        ])
        #expect(state.nextChange == Fixtures.date(2027, 5, 9, 17, 30))
    }

    /// Drawn again later than it was sent — gone stale, say — it starts from
    /// where the night stands rather than where it stood.
    @Test func drawnLateStartsFromWhereTheNightStands() throws {
        let state = try state(of: event(), at: Fixtures.date(2027, 5, 9, 16))
        let phases = state.phases(at: Fixtures.date(2027, 5, 9, 19, 10))
        #expect(phases.map(\.stage) == [.onNow, .wrapped])
        #expect(phases[0].from == nil)
        // Never back: a stage sent is not undone by a clock that reads earlier.
        #expect(state.phases(at: Fixtures.date(2027, 5, 9, 12)).first?.stage == .beforeDoors)
    }

    @Test func withNoDoorsTheShowComesNext() throws {
        let state = try state(of: event(doors: false), at: Fixtures.date(2027, 5, 9, 16))
        #expect(state.phases().map(\.stage) == [.beforeShow, .onNow, .wrapped])
        #expect(state.nextChange == Fixtures.date(2027, 5, 9, 19))
    }

    /// Doors inside the last few minutes open straight into "Starting in".
    @Test func doorsJustBeforeTheStartOpenIntoStartingSoon() throws {
        let event = Fixtures.event(date: Fixtures.date(2027, 5, 9),
                                   doorsOpen: Fixtures.date(2027, 5, 9, 18, 57),
                                   startsAt: Fixtures.date(2027, 5, 9, 19))
        let phases = try state(of: event, at: Fixtures.date(2027, 5, 9, 18)).phases()
        #expect(phases.map(\.stage) == [.beforeDoors, .startingSoon, .onNow, .wrapped])
        #expect(phases[1].from == Fixtures.date(2027, 5, 9, 18, 57))
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

    // MARK: - Started when it will last

    /// The reader's calendar, set to the hall's clock so a test machine
    /// anywhere counts the same days.
    var reader: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Fixtures.tokyo
        return calendar
    }

    /// Any day before, the sheet names the day rather than a time.
    @Test func isRefusedOnTheDaysBefore() {
        #expect(EventActivities.refusal(for: event(), at: Fixtures.date(2027, 5, 1), in: reader) == .beforeItsDay)
        #expect(EventActivities.refusal(for: event(), at: Fixtures.date(2027, 5, 8, 20), in: reader) == .beforeItsDay)
    }

    /// On the day itself, too early to last the night, it says from when.
    @Test func isRefusedUntilItWouldLastTheNight() {
        #expect(EventActivities.refusal(for: event(), at: Fixtures.date(2027, 5, 9, 10), in: reader)
                == .tooEarly(earliest: Fixtures.date(2027, 5, 9, 12, 30)))
    }

    @Test func startsOnceItWouldLastTheNight() {
        #expect(EventActivities.refusal(for: event(), at: Fixtures.date(2027, 5, 9, 12, 30), in: reader) == nil)
        #expect(EventActivities.refusal(for: event(), at: Fixtures.date(2027, 5, 9, 19), in: reader) == nil)
    }
}
