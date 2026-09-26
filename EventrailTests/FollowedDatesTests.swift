import Foundation
import Testing
@testable import Eventrail

@MainActor
struct FollowedDatesTests {
    private let performer = PerformerProfile(id: 1, name: "A", reading: nil, fanCount: nil, slug: "a")

    /// Every hall in Japan unless a test says otherwise.
    private func dates(
        _ events: [Event], zone: @escaping (Event) -> TimeZone? = { _ in Event.publishedZone }
    ) -> FollowedDates {
        let followed = FollowedDates(dates: [performer.id: events])
        followed.hallZone = zone
        return followed
    }

    @Test func aHallNotKnownToBeInJapanStaysUntilItsDayIsOut() {
        let now = Date.now
        let abroad = Fixtures.event(id: "abroad", date: now, startsAt: now.addingTimeInterval(-3 * 3600),
                                    endsAt: now.addingTimeInterval(-60))
        let followed = dates([abroad], zone: { _ in nil })
        #expect(followed.events(for: [performer]).map(\.id) == ["abroad"])
        followed.dropFinished()
        #expect(followed.dates[performer.id]?.map(\.id) == ["abroad"])
    }

    @Test func aHallAbroadIsJudgedAndShownOnItsOwnClock() throws {
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let now = Date.now
        // Read on Tokyo time, a finish an hour from now in Los Angeles looks
        // sixteen hours gone.
        let listed = Fixtures.event(id: "la", date: now.addingTimeInterval(-86400 / 2),
                                    startsAt: now.addingTimeInterval(-20 * 3600),
                                    endsAt: now.addingTimeInterval(-15 * 3600))
        let followed = dates([listed], zone: { _ in losAngeles })
        let shown = try #require(followed.events(for: [performer]).first)
        #expect(shown.timeZone == losAngeles)
        #expect(shown.endsAt == listed.published(in: losAngeles).endsAt)
        #expect(shown.endsAt! > now)
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
