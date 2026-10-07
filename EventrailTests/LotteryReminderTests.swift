import Foundation
import Testing
import UserNotifications
@testable import Eventrail

struct LotteryReminderTests {
    static let event = Fixtures.event(id: "live", title: "MyGO!!!!! 9th LIVE", date: Fixtures.day(fromToday: 60))

    static func list(_ entries: [LotteryEntry], for event: Event = event) -> LotteryList {
        LotteryList(events: [event]) { _ in Tracking(lotteries: entries) }
    }

    /// Today at `hour`, on the reader's clock.
    static func today(at hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
    }

    @Test func aRoundWaitingIsRemindedAtEightOnItsResultsDay() throws {
        let entry = LotteryEntry(round: "最速先行抽選", applications: 2, day: LotteryListTests.day(3))
        let due = LotteryReminder.due(in: Self.list([entry]))
        let reminder = try #require(due.first)
        #expect(due.count == 1)
        #expect(reminder.entryID == entry.id)
        #expect(reminder.eventID == "live")

        let trigger = try #require(reminder.request.trigger as? UNCalendarNotificationTrigger)
        let day = LotteryListTests.day(3)
        #expect(trigger.dateComponents.year == day.year)
        #expect(trigger.dateComponents.month == day.month)
        #expect(trigger.dateComponents.day == day.day)
        #expect(trigger.dateComponents.hour == 20)
        // Floating, so it comes at eight wherever the phone is.
        #expect(trigger.dateComponents.timeZone == nil)
        #expect(reminder.request.content.subtitle == "MyGO!!!!! 9th LIVE")
    }

    @Test func todayIsRemindedUntilEight() {
        let entry = LotteryEntry(round: "プレイガイド先行", day: LotteryListTests.day(0))
        #expect(LotteryReminder.due(in: Self.list([entry]), asOf: Self.today(at: 15)).count == 1)
        #expect(LotteryReminder.due(in: Self.list([entry]), asOf: Self.today(at: 21)).isEmpty)
    }

    @Test func onlyRoundsStillWaitingWithADayAreReminded() {
        let entries = [
            LotteryEntry(round: "最速先行抽選", day: LotteryListTests.day(2), result: .lost),
            LotteryEntry(round: "プレイガイド先行", day: LotteryListTests.day(2), result: .won(nil)),
            LotteryEntry(round: "プレイガイド二次先行"),
            // First come: nothing announced.
            LotteryEntry(round: "一般発売", day: LotteryListTests.day(2), choices: [LotteryChoice()]),
            .ticketHeld,
        ]
        #expect(LotteryReminder.due(in: Self.list(entries)).isEmpty)
    }

    @Test func anEventOverIsRemindedOfNothing() {
        let gone = Fixtures.event(id: "gone", date: Fixtures.day(fromToday: -2))
        let entry = LotteryEntry(round: "最速先行抽選", day: LotteryListTests.day(1))
        #expect(LotteryReminder.due(in: Self.list([entry], for: gone)).isEmpty)
    }

    @Test func theSoonestAreScheduledUpToTheLimit() {
        let entries = (1...70).reversed().map { LotteryEntry(round: "最速先行抽選", day: LotteryListTests.day($0)) }
        let due = LotteryReminder.due(in: Self.list(entries))
        #expect(due.count == LotteryReminder.limit)
        #expect(due.first?.day == LotteryListTests.day(1))
        #expect(due.map(\.day) == due.map(\.day).sorted())
    }

    @Test func aRoundWhoseDayHasComeIsStillWaitingForItsResult() {
        let out = LotteryEntry(round: "最速先行抽選", day: LotteryListTests.day(-1))
        let won = LotteryEntry(round: "プレイガイド先行", day: LotteryListTests.day(-1), result: .won(nil))
        let waiting = LotteryReminder.waiting(in: Self.list([out, won]))
        #expect(waiting == [LotteryReminder(LotteryRow(event: Self.event, entry: out))!.identifier])
    }

    @Test func aReminderMatchesOnlyItsOwnEveningAndWords() {
        let entry = LotteryEntry(round: "最速先行抽選", day: LotteryListTests.day(4))
        let reminder = LotteryReminder(LotteryRow(event: Self.event, entry: entry))!
        #expect(reminder.isScheduled(as: reminder.request))

        var moved = entry
        moved.day = LotteryListTests.day(5)
        #expect(!reminder.isScheduled(as: LotteryReminder(LotteryRow(event: Self.event, entry: moved))!.request))

        let retitled = Fixtures.event(id: "live", title: "MyGO!!!!! 9th LIVE Day 2", date: Fixtures.day(fromToday: 60))
        #expect(!reminder.isScheduled(as: LotteryReminder(LotteryRow(event: retitled, entry: entry))!.request))
        #expect(!reminder.isScheduled(as: nil))
    }
}
