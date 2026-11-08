import Foundation
import Testing
import UserNotifications
@testable import Eventrail

@MainActor
struct NewDateAlertTests {
    private let performer = PerformerProfile(id: 1, name: "A", reading: nil, fanCount: nil, slug: "a")

    // MARK: - What is news

    @Test func onlyADateNewToAListingAlreadyHeldIsNews() {
        let held = Fixtures.event(id: "held")
        let added = Fixtures.event(id: "added")
        let firstRead = Fixtures.event(id: "firstRead")
        // Performer 2 had no listing: every date of theirs arrives at once.
        let arrived = NewDateAlerts.arrivals(from: [1: [held]], to: [1: [held, added], 2: [firstRead]])
        #expect(arrived == ["added"])
    }

    @Test func aDateAnotherListingAlreadyHeldIsNotNews() {
        let shared = Fixtures.event(id: "shared")
        let arrived = NewDateAlerts.arrivals(from: [1: [], 2: [shared]], to: [1: [shared], 2: [shared]])
        #expect(arrived.isEmpty)
    }

    @Test func aDateGoneFromTheListingIsNotNews() {
        let gone = Fixtures.event(id: "gone")
        #expect(NewDateAlerts.arrivals(from: [1: [gone]], to: [1: []]).isEmpty)
    }

    @Test func aListingNeverReadIsStaleAtOnce() {
        let followed = FollowedDates(dates: [:])
        #expect(followed.staleAt(for: []) == nil)
        #expect(followed.staleAt(for: [performer]) == .distantPast)
    }

    // MARK: - What it says

    @Test func oneDateSaysWhoWhatWhenAndWhere() throws {
        let date = Fixtures.event(id: "9", title: "Tour Final", venue: "日本武道館",
                                  date: Fixtures.date(2027, 3, 14), startsAt: Fixtures.date(2027, 3, 14, 18))
        let alert = try #require(NewDateAlert(dates: [date], names: { _ in ["水瀬いのり"] }, clock: .venue))
        #expect(alert.title.contains("水瀬いのり"))
        #expect(alert.subtitle == "Tour Final")
        #expect(alert.body.hasPrefix(date.dayLine))
        #expect(alert.body.contains(try #require(date.timeLine)))
        #expect(alert.body.hasSuffix("日本武道館"))
        #expect(alert.events == ["9"])
    }

    @Test func aHallNobodyNamedIsLeftOut() throws {
        let date = Fixtures.event(venue: "!_東京都内某所")
        let alert = try #require(NewDateAlert(dates: [date], names: { _ in [] }, clock: .venue))
        #expect(alert.body == date.dayLine)
    }

    @Test func severalDatesAreCountedAndTheSoonestListed() throws {
        let dates = (1 ... 5).map { Fixtures.event(id: "\($0)", title: "Live \($0)") }
        let alert = try #require(NewDateAlert(dates: dates, names: { ["P\($0.id)"] }, clock: .venue))
        #expect(alert.title.contains("5"))
        let lines = alert.body.split(separator: "\n")
        #expect(lines.count == NewDateAlert.listed + 1)
        #expect(lines[0].hasSuffix("Live 1") && lines[2].hasSuffix("Live 3"))
        #expect(!alert.body.contains("Live 4"))
        #expect(alert.subtitle.contains("P3") && !alert.subtitle.contains("P4"))
        #expect(alert.events == ["1", "2", "3", "4", "5"])
    }

    @Test func nothingToSayIsNoAlert() {
        #expect(NewDateAlert(dates: [], names: { _ in [] }, clock: .venue) == nil)
    }

    /// Posted at once, so it takes none of the 64 pending the reminders
    /// share, and naming its dates where a tap reads them back.
    @Test func itComesAtOnceAndNamesItsDates() throws {
        let alert = try #require(NewDateAlert(dates: [Fixtures.event(id: "7")], names: { _ in [] }, clock: .venue))
        let request = alert.request
        #expect(request.trigger == nil)
        #expect(request.identifier.hasPrefix(NewDateAlert.prefix))
        #expect(NewDateAlert.events(in: request.content.userInfo) == ["7"])
        #expect(NewDateAlert.events(in: [:]).isEmpty)
    }
}
