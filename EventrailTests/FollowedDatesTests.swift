import Foundation
import Testing
@testable import Eventrail

@MainActor
struct FollowedDatesTests {
    private let performer = PerformerProfile(id: 1, name: "A", reading: nil, fanCount: nil, slug: "a")

    /// Every hall on Tokyo time unless a test says otherwise.
    private func dates(_ events: [Event], inJapan: @escaping (Event) -> Bool = { _ in true }) -> FollowedDates {
        let followed = FollowedDates(dates: [performer.id: events])
        followed.keepsPublishedClock = inJapan
        return followed
    }

    @Test func aHallNotKnownToBeInJapanStaysUntilItsDayIsOut() {
        let now = Date.now
        let abroad = Fixtures.event(id: "abroad", date: now, startsAt: now.addingTimeInterval(-3 * 3600),
                                    endsAt: now.addingTimeInterval(-60))
        let followed = dates([abroad], inJapan: { _ in false })
        #expect(followed.events(for: [performer]).map(\.id) == ["abroad"])
        followed.dropFinished()
        #expect(followed.dates[performer.id]?.map(\.id) == ["abroad"])
    }

    @Test func anEndPastMidnightIsTheNextMorning() {
        let now = Date.now
        // Started an hour ago; its "00:30" end was read onto the same day,
        // before the start.
        let late = Fixtures.event(id: "late", date: now, startsAt: now.addingTimeInterval(-3600),
                                  endsAt: now.addingTimeInterval(-7200))
        #expect(!late.hasEnded)
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
