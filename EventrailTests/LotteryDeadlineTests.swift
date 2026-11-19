import Foundation
import Testing
import UserNotifications
@testable import Eventrail

/// A round's results time and its application deadline: how they are kept, and
/// the notifications they bring (``LotteryReminder``, ``LotteryDeadlineAlert``).
struct LotteryDeadlineTests {
    static let event = LotteryReminderTests.event
    /// A day's lead, in minutes — what Settings opens on.
    static let day = 24 * 60

    /// `days` from today on Tokyo's calendar, the hall's, at `minute` on its
    /// clock — or the day alone.
    static func deadline(inDays days: Int, at minute: Int? = nil) -> LotteryDeadline {
        LotteryDeadline(day: CalendarDay(Fixtures.day(fromToday: days), in: .gregorian(in: Fixtures.tokyo)),
                        minute: minute)
    }

    static func row(_ entry: LotteryEntry, for event: Event = event) -> LotteryRow {
        LotteryRow(event: event, entry: entry)
    }

    // MARK: - Kept

    /// Both left out where nothing is written, so a round from before them is
    /// the same text, and not a change to send.
    @Test func aRoundFromBeforeThemReadsAndWritesBackAsItWas() throws {
        let text = #"{"applications":2,"day":"2026-10-12","id":"5A0B8C1E-7C11-4B7B-9D51-2F0E3C8A1B22","result":"pending","round":"最速先行抽選"}"#
        let entry = try #require(LotteryEntry.entry(inRow: text))
        #expect(entry.minute == nil)
        #expect(entry.deadline == nil)
        #expect(LotteryEntry.rowText(of: entry) == text)
    }

    @Test func theTimeAndTheDeadlineComeBack() throws {
        let entry = LotteryEntry(round: "最速先行抽選", day: LotteryListTests.day(9), minute: 18 * 60,
                                 deadline: Self.deadline(inDays: 4, at: 12 * 60))
        let text = LotteryEntry.rowText(of: entry)
        #expect(LotteryEntry.entry(inRow: text) == entry)

        // A deadline with no time writes none.
        var dayAlone = entry
        dayAlone.deadline?.minute = nil
        let dayAloneText = LotteryEntry.rowText(of: dayAlone)
        #expect(!dayAloneText.contains(#""minute":720"#))
        #expect(LotteryEntry.entry(inRow: dayAloneText) == dayAlone)
    }

    /// A deadline this build cannot read costs the deadline, not the round.
    @Test func aDeadlineItCannotReadCostsOnlyTheDeadline() throws {
        let text = #"{"applications":2,"deadline":{"minute":5},"id":"5A0B8C1E-7C11-4B7B-9D51-2F0E3C8A1B22","result":"pending","round":"最速先行抽選"}"#
        let entry = try #require(LotteryEntry.entry(inRow: text))
        #expect(entry.deadline == nil)
        #expect(entry.applications == 2)
    }

    /// A wall clock at the hall, as the notice prints it; a deadline's day
    /// alone closes at its last minute.
    @Test func bothAreInstantsAtTheHall() {
        let dayAlone = LotteryDeadline(day: CalendarDay(year: 2026, month: 11, day: 20))
        #expect(dayAlone.date(in: Fixtures.tokyo) == Fixtures.date(2026, 11, 20, 23, 59))
        #expect(dayAlone.alertDate(in: Fixtures.tokyo, lead: 60) == Fixtures.date(2026, 11, 20, 22, 59))
        let noon = LotteryDeadline(day: dayAlone.day, minute: 12 * 60)
        #expect(noon.date(in: Fixtures.tokyo) == Fixtures.date(2026, 11, 20, 12))
        #expect(noon.alertDate(in: Fixtures.tokyo, lead: Self.day) == Fixtures.date(2026, 11, 19, 12))

        let entry = LotteryEntry(day: CalendarDay(year: 2026, month: 12, day: 1), minute: 18 * 60)
        #expect(entry.resultsDate(in: Fixtures.tokyo) == Fixtures.date(2026, 12, 1, 18))
        #expect(LotteryEntry(day: entry.day).resultsDate(in: Fixtures.tokyo) == nil)
    }

    /// Applications close before anything is drawn: the deadline falls on a
    /// day before the results', and the results on a day after the
    /// deadline's — across a month's end, and a leap day, too.
    @Test func theDeadlineFallsBeforeTheResults() {
        let entry = LotteryEntry(day: CalendarDay(year: 2026, month: 12, day: 1),
                                 deadline: LotteryDeadline(day: CalendarDay(year: 2026, month: 11, day: 30)))
        #expect(entry.lastDeadlineDay == CalendarDay(year: 2026, month: 11, day: 30))
        #expect(entry.firstResultsDay == CalendarDay(year: 2026, month: 12, day: 1))
        #expect(LotteryEntry(day: entry.day).firstResultsDay == nil)
        #expect(LotteryEntry(deadline: entry.deadline).lastDeadlineDay == nil)
        #expect(CalendarDay(year: 2028, month: 3, day: 1).adding(days: -1) == CalendarDay(year: 2028, month: 2, day: 29))
        #expect(CalendarDay(year: 2026, month: 12, day: 31).adding(days: 1) == CalendarDay(year: 2027, month: 1, day: 1))
    }

    /// A time where one was written; a day alone, as a results day is.
    @Test func aDeadlineIsPrintedAsItWasWritten() {
        let day = CalendarDay(year: 2026, month: 11, day: 20)
        let noon = LotteryDeadline(day: day, minute: 12 * 60)
        #expect(Self.event.printedClosing(of: noon, on: .venue)
                == Self.event.printedMoment(noon.date(in: Self.event.timeZone), on: .venue))
        let dayAlone = Self.event.printedClosing(of: LotteryDeadline(day: day), on: .venue)
        #expect(dayAlone == day.date(in: .gregorian()).formatted(.gregorian().month().day()))
        #expect(!dayAlone.contains("23"))
    }

    // MARK: - The results time

    /// With a time beside the day, the reminder comes as the results come
    /// out, rather than at eight that evening.
    @Test func resultsWithATimeAreRemindedAtThatMoment() throws {
        let entry = LotteryEntry(round: "最速先行抽選", day: LotteryListTests.day(3), minute: 18 * 60)
        let reminder = try #require(LotteryReminder.due(in: LotteryReminderTests.list([entry])).first)
        let moment = try #require(entry.resultsDate(in: Self.event.timeZone))
        #expect(reminder.fires() == moment)

        let trigger = try #require(reminder.request.trigger as? UNTimeIntervalNotificationTrigger)
        let next = try #require(trigger.nextTriggerDate())
        #expect(abs(next.timeIntervalSince(moment)) < 5)
        #expect(reminder.isScheduled(as: reminder.request))

        var moved = entry
        moved.minute = 15 * 60
        #expect(!reminder.isScheduled(as: LotteryReminder(Self.row(moved))!.request))
        // Taken off, it comes at eight again: a different trigger altogether.
        moved.minute = nil
        #expect(!reminder.isScheduled(as: LotteryReminder(Self.row(moved))!.request))
    }

    @Test func aTimeGoneByIsRemindedOfNothing() {
        let entry = LotteryEntry(round: "最速先行抽選", day: LotteryListTests.day(1), minute: 18 * 60)
        let after = entry.resultsDate(in: Self.event.timeZone)!.addingTimeInterval(60)
        #expect(LotteryReminder.due(in: LotteryReminderTests.list([entry]), asOf: after).isEmpty)
    }

    // MARK: - The deadline's alert

    @Test func aRoundWaitingIsWarnedAheadOfItsDeadline() throws {
        let deadline = Self.deadline(inDays: 5, at: 18 * 60)
        let entry = LotteryEntry(round: "最速先行抽選", applications: 2, deadline: deadline)
        let alert = try #require(LotteryDeadlineAlert.due(in: LotteryReminderTests.list([entry]), lead: Self.day).first)
        #expect(alert.entryID == entry.id)
        #expect(alert.date == deadline.alertDate(in: Self.event.timeZone, lead: Self.day))
        #expect(alert.identifier.hasPrefix(LotteryDeadlineAlert.prefix))
        #expect(!alert.identifier.hasPrefix(LotteryReminder.prefix))

        let request = alert.request
        // Read by the delegate as a results-day reminder is: the ticket sheet
        // on that round.
        #expect(request.content.userInfo[LotteryReminder.eventKey] as? String == Self.event.id)
        #expect(request.content.userInfo[LotteryReminder.entryKey] as? String == entry.id.uuidString)
        #expect(request.content.subtitle == Self.event.title)
        #expect(request.content.body.contains(LotteryRound.label(of: entry.round)))
        #expect(request.content.body.contains(Self.event.printedClosing(of: deadline, on: .venue)))
        let next = try #require((request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate())
        #expect(abs(next.timeIntervalSince(alert.date)) < 5)
        #expect(alert.isScheduled(as: request))
    }

    /// A day ahead can wait for a Focus to end; an hour before it closes
    /// can't — as an event's own reminders have it.
    @Test func itIsTimeSensitiveUnderADaysLead() throws {
        let row = Self.row(LotteryEntry(round: "最速先行抽選", deadline: Self.deadline(inDays: 5)))
        let calm = try #require(LotteryDeadlineAlert(row, lead: Self.day))
        let urgent = try #require(LotteryDeadlineAlert(row, lead: 60))
        #expect(!calm.isTimeSensitive)
        #expect(calm.request.content.interruptionLevel == .active)
        #expect(urgent.request.content.interruptionLevel == .timeSensitive)
    }

    @Test func onlyALotteryStillWaitingIsWarned() {
        let ahead = Self.deadline(inDays: 5)
        let entries = [
            LotteryEntry(round: "最速先行抽選", deadline: ahead, result: .lost),
            LotteryEntry(round: "プレイガイド先行", deadline: ahead, result: .won(nil)),
            // First come: nothing to apply for.
            LotteryEntry(round: "一般発売", deadline: ahead, choices: [LotteryChoice()]),
        ]
        #expect(LotteryDeadlineAlert.due(in: LotteryReminderTests.list(entries), lead: Self.day).isEmpty)
    }

    /// A week ahead of a deadline two days off has been; an hour ahead of it
    /// is still to come.
    @Test func noAlertComesOnceItsMomentHasBeen() {
        let list = LotteryReminderTests.list([LotteryEntry(round: "最速先行抽選", deadline: Self.deadline(inDays: 2))])
        #expect(LotteryDeadlineAlert.due(in: list, lead: 7 * Self.day).isEmpty)
        #expect(LotteryDeadlineAlert.due(in: list, lead: 60).count == 1)
    }

    /// An event moved to an earlier day leaves its round's deadline where it
    /// was written: past the event's day, nothing is scheduled to come after
    /// the event is over. On the day itself it still comes.
    @Test func aDeadlinePastTheEventsDayIsWarnedOfNothing() {
        let moved = Fixtures.event(id: "live", title: "MyGO!!!!! 9th LIVE", date: Fixtures.day(fromToday: 5))
        let past = LotteryEntry(round: "最速先行抽選", deadline: Self.deadline(inDays: 10))
        let onTheDay = LotteryEntry(round: "プレイガイド先行", deadline: Self.deadline(inDays: 5))
        #expect(LotteryDeadlineAlert(Self.row(past, for: moved), lead: Self.day) == nil)
        #expect(LotteryDeadlineAlert(Self.row(onTheDay, for: moved), lead: Self.day) != nil)
    }

    @Test func anAlertShownStandsUntilTheDeadlinePasses() {
        let open = LotteryEntry(round: "最速先行抽選", deadline: Self.deadline(inDays: 3))
        let closed = LotteryEntry(round: "プレイガイド先行", deadline: Self.deadline(inDays: -2))
        let decided = LotteryEntry(round: "最速先行抽選", deadline: Self.deadline(inDays: 3), result: .lost)
        let standing = LotteryDeadlineAlert.standing(in: LotteryReminderTests.list([open, closed, decided]))
        #expect(standing == [LotteryDeadlineAlert.identifier(of: open.id, at: Self.event.id)])
    }

    @Test func anAlertMatchesOnlyItsOwnMomentAndWords() throws {
        let entry = LotteryEntry(round: "最速先行抽選", deadline: Self.deadline(inDays: 6))
        let alert = try #require(LotteryDeadlineAlert(Self.row(entry), lead: Self.day))

        var moved = entry
        moved.deadline?.minute = 18 * 60
        let movedAlert = try #require(LotteryDeadlineAlert(Self.row(moved), lead: Self.day))
        #expect(!alert.isScheduled(as: movedAlert.request))

        // Another lead in Settings: another moment, and under a day Time
        // Sensitive too.
        let sooner = try #require(LotteryDeadlineAlert(Self.row(entry), lead: 60))
        #expect(!alert.isScheduled(as: sooner.request))
        #expect(!alert.isScheduled(as: nil))
    }

    // MARK: - Together

    /// The results days and the deadlines share one limit, the soonest first,
    /// so the other reminders keep their share of iOS's 64.
    @Test func resultsAndDeadlinesShareOneLimit() {
        let results = (1...30).map { LotteryEntry(round: "最速先行抽選", day: LotteryListTests.day($0 * 2)) }
        let deadlines = (1...30).map { LotteryEntry(round: "プレイガイド先行", deadline: Self.deadline(inDays: $0 * 2 + 1)) }
        let due = LotteryAlert.due(in: LotteryReminderTests.list(results + deadlines), deadlineLead: Self.day)
        #expect(due.count == LotteryReminder.limit)
        #expect(due.contains { if case .deadline = $0 { true } else { false } })
        #expect(due.contains { if case .results = $0 { true } else { false } })
        #expect(due.allSatisfy { LotteryAlert.isOwn($0.identifier) })
        #expect(Set(due.map(\.identifier)).count == due.count)
    }

    /// No Alert in Settings: the results days alone.
    @Test func noLeadWarnsOfNoDeadline() {
        let entries = [LotteryEntry(round: "最速先行抽選", day: LotteryListTests.day(8)),
                       LotteryEntry(round: "プレイガイド先行", deadline: Self.deadline(inDays: 5))]
        let due = LotteryAlert.due(in: LotteryReminderTests.list(entries), deadlineLead: nil)
        #expect(due.count == 1)
        #expect(due.allSatisfy { if case .results = $0 { true } else { false } })
    }
}
