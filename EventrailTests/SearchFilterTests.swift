import Foundation
import Testing
@testable import Eventrail

struct SearchFilterTests {
    private let ahead = Fixtures.event(id: "ahead", date: Fixtures.day(fromToday: 10))
    private let past = Fixtures.event(id: "past", date: Fixtures.day(fromToday: -10))

    @Test func anyWhenKeepsBothHalves() {
        let filter = SearchFilter()
        #expect(filter.matches(ahead))
        #expect(filter.matches(past))
        #expect(!filter.holdsRows)
    }

    @Test func upcomingAndPastSplitTheListing() {
        let upcoming = SearchFilter(when: .upcoming)
        #expect(upcoming.matches(ahead))
        #expect(!upcoming.matches(past))

        let gone = SearchFilter(when: .past)
        #expect(!gone.matches(ahead))
        #expect(gone.matches(past))
    }

    /// Read newest first, the upcoming nights come first: a past row ends the
    /// upcoming ones, and an upcoming row is in front of the past ones.
    @Test func newestFirstSkipsTheNightsAheadAndStopsAtThePastOnes() {
        let upcoming = SearchFilter(when: .upcoming)
        #expect(upcoming.comesAfterMatches(past, reading: .newestFirst))
        #expect(!upcoming.comesAfterMatches(ahead, reading: .newestFirst))
        #expect(!upcoming.comesBeforeMatches(ahead, reading: .newestFirst))

        let gone = SearchFilter(when: .past)
        #expect(gone.comesBeforeMatches(ahead, reading: .newestFirst))
        #expect(!gone.comesBeforeMatches(past, reading: .newestFirst))
        #expect(!gone.comesAfterMatches(past, reading: .newestFirst))
    }

    /// Oldest first, the same edges swap ends: every past night is in front
    /// of the first upcoming one.
    @Test func oldestFirstSwapsTheEnds() {
        let upcoming = SearchFilter(when: .upcoming)
        #expect(upcoming.comesBeforeMatches(past, reading: .oldestFirst))
        #expect(!upcoming.comesBeforeMatches(ahead, reading: .oldestFirst))
        #expect(!upcoming.comesAfterMatches(ahead, reading: .oldestFirst))

        let gone = SearchFilter(when: .past)
        #expect(gone.comesAfterMatches(ahead, reading: .oldestFirst))
        #expect(!gone.comesBeforeMatches(past, reading: .oldestFirst))
    }

    @Test func noFilterNeverSkipsOrStops() {
        let filter = SearchFilter(area: .overseas)
        for order in SearchOrder.allCases {
            #expect(!filter.comesBeforeMatches(past, reading: order))
            #expect(!filter.comesAfterMatches(ahead, reading: order))
        }
    }

    @Test func anAreaIsTheSitesOwnNumber() {
        #expect(SearchFilter.Area.all.map(\.areaID) == [1, 2, 3, 4, 5, 6])
    }

    /// The area is the site's to answer, so it holds no row back here.
    @Test func anAreaAloneHoldsNothingBackHere() {
        let filter = SearchFilter(area: .region(.kanto))
        #expect(filter.isNarrowing)
        #expect(!filter.holdsRows)
    }
}
