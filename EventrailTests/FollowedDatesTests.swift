import Foundation
import Testing
@testable import Eventrail

@MainActor
struct FollowedDatesTests {
    private let performer = PerformerProfile(id: 1, name: "A", reading: nil, fanCount: nil, slug: "a")

    private func dates(_ events: [Event]) -> FollowedDates {
        FollowedDates(dates: [performer.id: events])
    }

    @Test func aNightWhoseEndHasPassedIsGoneThoughItsDayIsNot() {
        let now = Date.now
        let over = Fixtures.event(id: "over", date: now, startsAt: now.addingTimeInterval(-3 * 3600),
                                  endsAt: now.addingTimeInterval(-60))
        let on = Fixtures.event(id: "on", date: now, startsAt: now.addingTimeInterval(-3600),
                                endsAt: now.addingTimeInterval(3600))
        // No end published: nothing says it is over before the day is.
        let open = Fixtures.event(id: "open", date: now, startsAt: now.addingTimeInterval(-3 * 3600))
        let followed = dates([over, on, open])
        #expect(followed.events(for: [performer]).map(\.id).sorted() == ["on", "open"])
        #expect(followed.count(for: performer) == 2)
    }
}

extension FollowedDatesTests {
    @Test func finishedNightsLeaveTheCacheItself() {
        let now = Date.now
        let over = Fixtures.event(id: "over", date: now, startsAt: now.addingTimeInterval(-3 * 3600),
                                  endsAt: now.addingTimeInterval(-60))
        let on = Fixtures.event(id: "on", date: now.addingTimeInterval(86400))
        let followed = dates([over, on])
        followed.dropFinished()
        #expect(followed.dates[performer.id]?.map(\.id) == ["on"])
    }
}
