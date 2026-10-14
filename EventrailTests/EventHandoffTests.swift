import Foundation
import Testing
@testable import Eventrail

struct EventHandoffTests {
    private let event = Fixtures.event(
        id: "412345", title: "Liella! 6th", venue: "大阪城ホール", venueAddress: "大阪府大阪市中央区大阪城3-1",
        date: Fixtures.date(2025, 6, 14), startsAt: Fixtures.date(2025, 6, 14, 15, 30),
        performers: ["伊達さゆり"], summary: String(repeating: "一般発売 6/1 10:00〜\n", count: 200),
        isDetailed: true, detailFormat: Event.currentDetailFormat)

    private func continued(_ event: Event) -> NSUserActivity {
        let activity = NSUserActivity(activityType: EventHandoff.activityType)
        EventHandoff.fill(activity, with: event)
        return activity
    }

    @Test func aDeviceWithoutTheAppIsSentToTheEventsPage() {
        let activity = continued(event)
        #expect(activity.webpageURL == event.sourceURL)
        #expect(activity.isEligibleForHandoff)
    }

    @Test func carriesWhatARowPrintsAndLeavesThePagesWritingBehind() throws {
        let sent = try #require(EventHandoff.event(in: continued(event)))
        #expect(sent.id == event.id)
        #expect(sent.title == event.title)
        #expect(sent.startsAt == event.startsAt)
        #expect(sent.timeZone == event.timeZone)
        #expect(sent.venueAddress == event.venueAddress)
        #expect(sent.performers == event.performers)
        #expect(sent.summary == nil)
        let payload = try #require(EventHandoff.payload(for: event))
        #expect(payload.count < 3_000)
    }

    @Test func theSheetThatOpensOnTheCopyReadsThePage() throws {
        let sent = try #require(EventHandoff.event(in: continued(event)))
        #expect(sent.isDetailed)
        #expect(!sent.isFullyDetailed)
    }

    @Test func aCopyThisBuildCannotReadIsNoEvent() {
        let activity = NSUserActivity(activityType: EventHandoff.activityType)
        activity.userInfo = ["event": Data("{\"id\":1}".utf8)]
        #expect(EventHandoff.event(in: activity) == nil)
    }
}
