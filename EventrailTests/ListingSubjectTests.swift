import Foundation
import Testing
@testable import Eventrail

/// Which events a performer's or a hall's "You attended" and the reader's
/// history with them count — see ``ListingSubject/includes(_:)``.
struct ListingSubjectTests {
    @Test func matchesByThePrintedName() {
        let show = Fixtures.event(venue: "Hall", performers: ["A", "B"])
        #expect(ListingSubject.performer("A").includes(show))
        #expect(!ListingSubject.performer("C").includes(show))
        #expect(ListingSubject.venue("Hall").includes(show))
        #expect(!ListingSubject.venue("Other Hall").includes(show))
    }
}
