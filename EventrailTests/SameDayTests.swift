import Foundation
import Testing
@testable import Eventrail

struct SameDayTests {
    /// An event on 9 May 2027 in Tokyo, starting at `start` and ending at
    /// `end` where given, as hours and minutes on the hall's clock.
    static func event(
        _ id: String, venue: String = "Hall",
        start: (Int, Int)? = nil, end: (Int, Int)? = nil, day: Int = 9
    ) -> Event {
        Fixtures.event(
            id: id, venue: venue,
            date: Fixtures.date(2027, 5, day),
            startsAt: start.map { Fixtures.date(2027, 5, day, $0.0, $0.1) },
            endsAt: end.map { Fixtures.date(2027, 5, day, $0.0, $0.1) })
    }

    @Test func ordersTheTwoByWhenTheyStart() {
        let evening = Self.event("evening", start: (18, 0))
        let afternoon = Self.event("afternoon", start: (13, 0))
        let pair = SameDay(evening, afternoon)
        #expect(pair.earlier.id == "afternoon")
        #expect(pair.later.id == "evening")
        #expect(pair.other(than: evening).id == "afternoon")
    }

    @Test func aStartBeforeTheOtherEndsIsAnOverlap() {
        let first = Self.event("first", venue: "武道館", start: (13, 0), end: (16, 0))
        let second = Self.event("second", venue: "横浜アリーナ", start: (15, 30), end: (18, 0))
        #expect(SameDay(first, second).timing == .overlapping(by: 30 * 60, endIsAssumed: false))
        #expect(SameDay(first, second).clash(travel: nil) == .overlap)
    }

    @Test func anOverlapNoEndWasPublishedForIsSaidToBeAssumed() {
        // 13:00 and no end runs to 16:00.
        let first = Self.event("first", start: (13, 0))
        let second = Self.event("second", venue: "Other Hall", start: (15, 0))
        #expect(SameDay(first, second).timing == .overlapping(by: 60 * 60, endIsAssumed: true))
    }

    @Test func anOverlapIsOnlyAsLongAsTheShorterOfTheTwo() {
        let long = Self.event("long", start: (12, 0), end: (20, 0))
        let short = Self.event("short", venue: "Other Hall", start: (14, 0), end: (15, 0))
        #expect(SameDay(long, short).timing == .overlapping(by: 60 * 60, endIsAssumed: false))
    }

    @Test func twoShowsAtOneHallNeedNoJourney() {
        let matinee = Self.event("昼", venue: "武道館", start: (13, 0), end: (15, 30))
        let evening = Self.event("夜", venue: "武道館", start: (18, 0))
        let pair = SameDay(matinee, evening)
        #expect(pair.timing == .sameHall(gap: 2.5 * 60 * 60))
        #expect(!pair.needsTravel)
        #expect(pair.clash(travel: 10 * 60 * 60) == nil)
    }

    @Test func twoHallsAreAJourneyFromTheFirstEndToTheSecondStart() {
        let first = Self.event("first", venue: "武道館", start: (13, 0), end: (15, 0))
        let second = Self.event("second", venue: "横浜アリーナ", start: (16, 0))
        let pair = SameDay(first, second)
        #expect(pair.timing == .apart(gap: 60 * 60))
        #expect(pair.needsTravel)
        #expect(pair.departure == Fixtures.date(2027, 5, 9, 15, 0))
        #expect(pair.clash(travel: nil) == nil)
        #expect(pair.clash(travel: 45 * 60) == nil)
        #expect(pair.clash(travel: 60 * 60) == nil)
        #expect(pair.clash(travel: 75 * 60) == .tightTransfer)
    }

    @Test func aStreamIsNoHallToTravelTo() {
        let show = Self.event("show", venue: "武道館", start: (13, 0), end: (15, 0))
        let stream = Self.event("stream", venue: "!_国内外各所 (ライブビューイング等)", start: (16, 0))
        let pair = SameDay(show, stream)
        #expect(pair.timing == .apart(gap: 60 * 60))
        #expect(!pair.needsTravel)
        #expect(pair.clash(travel: 2 * 60 * 60) == nil)
    }

    @Test func nothingIsSaidWithoutBothStarts() {
        let timed = Self.event("timed", start: (13, 0))
        let untimed = Self.event("untimed")
        #expect(SameDay(timed, untimed).timing == .untimed)
        #expect(SameDay(timed, untimed).clash(travel: nil) == nil)
    }

    @Test func anEndPastMidnightIsTheNextMorning() {
        // 22:00 to 02:00 is not an event that ended before it began.
        let late = Self.event("late", venue: "Club", start: (22, 0), end: (2, 0))
        let span = SameDay.span(of: late)
        #expect(span?.ends == Fixtures.date(2027, 5, 10, 2, 0))
        #expect(span?.endIsAssumed == false)
    }

    @Test func pairsAnEventWithTheOthersOfItsDayAlone() {
        let this = Self.event("this", start: (18, 0))
        let others = [
            this,
            Self.event("later", venue: "B", start: (21, 0)),
            Self.event("earlier", venue: "A", start: (12, 0)),
            Self.event("tomorrow", venue: "C", start: (12, 0), day: 10),
        ]
        let pairs = SameDay.pairs(of: this, among: others)
        #expect(pairs.map { $0.other(than: this).id } == ["earlier", "later"])
    }

    @Test func marksEveryEventOfAListByItsWorstClash() {
        let a = Self.event("a", venue: "A", start: (13, 0), end: (15, 0))
        let b = Self.event("b", venue: "B", start: (14, 30), end: (16, 0))
        let c = Self.event("c", venue: "C", start: (17, 0))
        let d = Self.event("d", venue: "D", start: (12, 0), day: 10)
        let clashes = SameDay.clashes(in: [a, b, c, d]) { pair in
            // B to C is an hour and a half; everything else is close.
            pair.earlier.id == "b" && pair.later.id == "c" ? 90 * 60 : 5 * 60
        }
        #expect(clashes == ["a": .overlap, "b": .overlap, "c": .tightTransfer])
    }

    @Test func aJourneyIsAskedAgainOnceAnEventMoves() {
        let first = Self.event("first", venue: "A", start: (13, 0), end: (15, 0))
        let second = Self.event("second", venue: "B", start: (17, 0))
        let moved = Self.event("first", venue: "A", start: (13, 0), end: (15, 30))
        #expect(TravelTimes.key(for: SameDay(first, second)) == TravelTimes.key(for: SameDay(second, first)))
        #expect(TravelTimes.key(for: SameDay(first, second)) != TravelTimes.key(for: SameDay(moved, second)))
    }
}
