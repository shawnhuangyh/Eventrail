import Foundation
import Testing
@testable import Eventrail

struct VenuePlacesTests {
    private let seoul = TimeZone(identifier: "Asia/Seoul")!
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    @Test func aHallNameIsLookedUpHoweverItWasPadded() {
        let zones = VenuePlaces.zonesByName([(" Legacy Taipei\n", Fixtures.taipei)])
        #expect(zones["Legacy Taipei"] == Fixtures.taipei)
    }

    /// One name, two halls in different countries: a row naming it could be
    /// either, so it gets no clock rather than whichever was written last.
    @Test func aNameTwoHallsShareOnDifferentClocksAnswersNothing() {
        let zones = VenuePlaces.zonesByName([("Grand Hall", seoul), ("Grand Hall", Fixtures.taipei)])
        #expect(zones["Grand Hall"] == nil)
    }

    /// London and Accra share an offset all winter and part in summer: one
    /// name placed in both has no clock a summer date can be read on.
    @Test func zonesThatPartForSummerAreDifferentClocks() {
        let zones = VenuePlaces.zonesByName([("Grand Hall", TimeZone(identifier: "Europe/London")!),
                                             ("Grand Hall", TimeZone(identifier: "Africa/Accra")!)])
        #expect(zones["Grand Hall"] == nil)
    }

    /// Counted from the last time anything wanted the answer, not from the
    /// asking: counted so, every hall a first import placed went on one day,
    /// a year later, however often the reader went back.
    @Test func anAnswerLapsesAYearAfterItWasLastWanted() {
        let now = Fixtures.date(2027, 10, 1)
        let imported = Fixtures.date(2026, 9, 18)
        #expect(!VenuePlaces.hasLapsed(asked: imported, used: Fixtures.date(2027, 9, 24), now: now))
        #expect(VenuePlaces.hasLapsed(asked: imported, used: nil, now: now))
        #expect(VenuePlaces.hasLapsed(asked: imported, used: Fixtures.date(2026, 9, 30), now: now))
        // Asked again since, it counts from then.
        #expect(!VenuePlaces.hasLapsed(asked: Fixtures.date(2027, 3, 1), used: Fixtures.date(2026, 9, 20), now: now))
    }

    /// A hall Maps has not placed is searched for by name, the name whole: an
    /// `&` left bare ended the query, and a `+` reads as a space.
    @Test func aHallIsSearchedForInMapsByItsWholeName() throws {
        let url = try #require(VenueDirections.searchURL("HMV&BOOKS SHIBUYA +α", directions: true))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query == [URLQueryItem(name: "daddr", value: "HMV&BOOKS SHIBUYA +α")])
        #expect(url.absoluteString.contains("%26BOOKS%20SHIBUYA%20%2B"))
        #expect(VenueDirections.searchURL("", directions: false) == nil)
    }

    /// A read is every launch and every mirror, so it is written down at most
    /// once a month.
    @Test func aReadIsNotedAtMostOnceAMonth() {
        let now = Fixtures.date(2027, 10, 1)
        let imported = Fixtures.date(2026, 9, 18)
        #expect(!VenuePlaces.isWorthNoting(asked: imported, used: Fixtures.date(2027, 9, 20), now: now))
        #expect(VenuePlaces.isWorthNoting(asked: imported, used: Fixtures.date(2027, 8, 20), now: now))
        #expect(VenuePlaces.isWorthNoting(asked: imported, used: nil, now: now))
        #expect(!VenuePlaces.isWorthNoting(asked: Fixtures.date(2027, 9, 28), used: nil, now: now))
    }

    /// Two answers of one hour — Maps filing a Taipei hall under Shanghai on a
    /// mainland phone — are one clock.
    @Test func aNameTwoPlacingsAgreeOnKeepsItsClock() {
        let zones = VenuePlaces.zonesByName([("Grand Hall", Fixtures.taipei), ("Grand Hall", shanghai)])
        #expect(zones["Grand Hall"]?.secondsFromGMT() == Fixtures.taipei.secondsFromGMT())
    }
}
