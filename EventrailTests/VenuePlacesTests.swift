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

    /// Two answers of one hour — Maps filing a Taipei hall under Shanghai on a
    /// mainland phone — are one clock.
    @Test func aNameTwoPlacingsAgreeOnKeepsItsClock() {
        let zones = VenuePlaces.zonesByName([("Grand Hall", Fixtures.taipei), ("Grand Hall", shanghai)])
        #expect(zones["Grand Hall"]?.secondsFromGMT() == Fixtures.taipei.secondsFromGMT())
    }
}
