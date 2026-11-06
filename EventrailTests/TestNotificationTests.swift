#if DEBUG
import Foundation
import Testing
import UserNotifications
@testable import Eventrail

/// What the debug bench sends: a real notification under a name of its own —
/// see ``TestNotification``.
@MainActor
struct TestNotificationTests {
    func real() throws -> UNNotificationRequest {
        let show = Fixtures.event(date: Fixtures.day(fromToday: 3))
        return try #require(ReminderAlert(reminder: EventReminder(kind: .goodsSale, for: show), event: show)).request
    }

    @Test func itSaysWhatTheRealOneSays() throws {
        let real = try real()
        let test = TestNotification.request(standingInFor: real, in: 10)
        #expect(test.content.title == real.content.title)
        #expect(test.content.subtitle == real.content.subtitle)
        #expect(test.content.body == real.content.body)
        #expect(test.content.interruptionLevel == real.content.interruptionLevel)
        #expect(test.content.threadIdentifier == real.content.threadIdentifier)
        #expect(test.content.userInfo[ReminderAlert.eventKey] as? String
                == real.content.userInfo[ReminderAlert.eventKey] as? String)
        #expect((test.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval == 10)
    }

    /// Each reminder takes back what it finds under its own prefix and the
    /// library does not call for, which a test would be.
    @Test func theAppsOwnSchedulingLeavesItAlone() throws {
        let show = Fixtures.event(date: Fixtures.day(fromToday: 3))
        let reals = [try real(),
                     LotteryReminder(testing: show, entry: nil).request,
                     ActivityReminder(testing: show).request]
        for real in reals {
            let test = TestNotification.request(standingInFor: real, in: 10).identifier
            #expect(!test.hasPrefix(ReminderAlert.prefix))
            #expect(!test.hasPrefix(LotteryReminder.prefix))
            #expect(!test.hasPrefix(ActivityReminder.prefix))
        }
    }

    @Test func aTapGoesWhereTheRealOnesGoes() throws {
        let real = try real()
        let test = TestNotification.request(standingInFor: real, in: 10)
        #expect(TestNotification.routed(test.identifier).hasPrefix(ReminderAlert.prefix))
        #expect(TestNotification.routed(real.identifier) == real.identifier)
    }

    /// So several can be sent to watch them stack.
    @Test func eachOneSentStandsApart() throws {
        let real = try real()
        #expect(TestNotification.request(standingInFor: real, in: 10).identifier
                != TestNotification.request(standingInFor: real, in: 10).identifier)
    }

    /// The app itself owes nothing here, and the bench can still send it.
    @Test func anEventGoneByCanBeSentOne() {
        let over = Fixtures.event(date: Fixtures.day(fromToday: -3))
        let reminder = EventReminder(kind: .goodsSale, for: over, at: over.date)
        #expect(ReminderAlert(reminder: reminder, event: over) == nil)
        #expect(ReminderAlert(reminder: reminder, event: over, at: .distantPast) != nil)
    }

    @Test func aRoundIsNamedWhereThereIsOne() {
        let show = Fixtures.event(date: Fixtures.day(fromToday: 3))
        let entry = LotteryEntry(round: LotteryRound.first.rawValue)
        let reminder = LotteryReminder(testing: show, entry: entry)
        #expect(reminder.entryID == entry.id)
        #expect(reminder.round == LotteryRound.first.rawValue)
        #expect(!LotteryReminder(testing: show, entry: nil).round.isEmpty)
    }
}
#endif
